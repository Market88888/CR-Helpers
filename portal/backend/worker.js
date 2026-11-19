const ONLINE_TTL = 120;
const RATE_TTL = 86400;
const RATE_FIELDS = ['vc', 'btc', 'az', 'aarp', 'asc'];

function json(data, status = 200, origin = '*') {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': origin,
      'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers': 'Content-Type',
      'access-control-max-age': '86400',
      'x-content-type-options': 'nosniff',
    },
  });
}

function cleanText(value, max) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, max)
    : '';
}

async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function finiteRate(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 && n <= 1e12 ? n : null;
}

function median(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

async function handleApi(request, env, origin) {
  if (!env.DB) return json({ error: 'backend_not_configured' }, 503, origin);
  const url = new URL(request.url);
  const now = Math.floor(Date.now() / 1000);

  if (request.method === 'GET' && url.pathname === '/api/players') {
    const { results = [] } = await env.DB.prepare(
      'SELECT nickname, server_name AS server, last_seen AS lastSeen FROM online_players WHERE expires_at > ? ORDER BY server_name, nickname LIMIT 500'
    ).bind(now).all();
    return json({ players: results, count: results.length, updatedAt: new Date().toISOString() }, 200, origin);
  }

  if (request.method === 'GET' && url.pathname === '/api/rates') {
    const { results = [] } = await env.DB.prepare(
      'SELECT server_name, vc, btc, az, aarp, asc, updated_at FROM rate_reports WHERE updated_at > ? ORDER BY server_name, updated_at DESC LIMIT 2000'
    ).bind(now - RATE_TTL).all();
    const grouped = new Map();
    for (const row of results) {
      let item = grouped.get(row.server_name);
      if (!item) {
        item = { server: row.server_name, values: Object.fromEntries(RATE_FIELDS.map((key) => [key, []])), updated: 0, sources: 0 };
        grouped.set(row.server_name, item);
      }
      item.sources++;
      item.updated = Math.max(item.updated, row.updated_at);
      for (const key of RATE_FIELDS) if (Number.isFinite(row[key])) item.values[key].push(row[key]);
    }
    const rates = [...grouped.values()].map((item) => ({
      server: item.server,
      ...Object.fromEntries(RATE_FIELDS.map((key) => [key, median(item.values[key])])),
      sources: item.sources,
      updated: new Date(item.updated * 1000).toISOString(),
    }));
    return json({ rates, updatedAt: new Date().toISOString() }, 200, origin);
  }

  if (request.method === 'POST' && url.pathname === '/api/heartbeat') {
    if (Number(request.headers.get('content-length') || 0) > 4096) return json({ error: 'payload_too_large' }, 413, origin);
    let body;
    try { body = await request.json(); } catch (_) { return json({ error: 'invalid_json' }, 400, origin); }
    if (body?.consent !== true) return json({ error: 'consent_required' }, 403, origin);
    const clientId = cleanText(body.clientId, 100);
    const nickname = cleanText(body.nickname, 32);
    const server = cleanText(body.server, 48);
    if (clientId.length < 24 || !nickname || !server) return json({ error: 'invalid_fields' }, 400, origin);
    const rates = body.rates && typeof body.rates === 'object' ? body.rates : null;
    let rateValues = null;
    if (rates) {
      rateValues = RATE_FIELDS.map((key) => finiteRate(rates[key]));
      if (rateValues.some((v) => v !== null) && rateValues.some((v) => v === null)) return json({ error: 'invalid_rates' }, 400, origin);
      if (!rateValues.some((v) => v !== null)) rateValues = null;
    }
    const idHash = await digest(clientId);
    await env.DB.prepare(
      'INSERT INTO online_players (id_hash, nickname, server_name, last_seen, expires_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id_hash) DO UPDATE SET nickname=excluded.nickname, server_name=excluded.server_name, last_seen=excluded.last_seen, expires_at=excluded.expires_at'
    ).bind(idHash, nickname, server, now, now + ONLINE_TTL).run();

    if (rateValues) {
        await env.DB.prepare(
          'INSERT INTO rate_reports (id_hash, server_name, vc, btc, az, aarp, asc, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id_hash, server_name) DO UPDATE SET vc=excluded.vc, btc=excluded.btc, az=excluded.az, aarp=excluded.aarp, asc=excluded.asc, updated_at=excluded.updated_at'
        ).bind(idHash, server, ...rateValues, now).run();
    }
    return json({ ok: true, expiresIn: ONLINE_TTL }, 200, origin);
  }

  if ((request.method === 'DELETE' && url.pathname === '/api/me') || (request.method === 'POST' && url.pathname === '/api/optout')) {
    let body;
    try { body = await request.json(); } catch (_) { return json({ error: 'invalid_json' }, 400, origin); }
    const clientId = cleanText(body?.clientId, 100);
    if (clientId.length < 24) return json({ error: 'invalid_fields' }, 400, origin);
    const idHash = await digest(clientId);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM online_players WHERE id_hash = ?').bind(idHash),
      env.DB.prepare('DELETE FROM rate_reports WHERE id_hash = ?').bind(idHash),
    ]);
    return json({ ok: true, removed: true }, 200, origin);
  }

  return json({ error: 'not_found' }, 404, origin);
}

export default {
  async fetch(request, env) {
    const origin = env.SITE_ORIGIN || '*';
    if (request.method === 'OPTIONS') return json({}, 200, origin);
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/')) {
      try { return await handleApi(request, env, origin); }
      catch (_) { return json({ error: 'server_error' }, 500, origin); }
    }
    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response('PC Stats site assets are not bound.', { status: 404 });
  },
  async scheduled(_event, env, ctx) {
    const cutoff = Math.floor(Date.now() / 1000);
    ctx.waitUntil(env.DB.batch([
      env.DB.prepare('DELETE FROM online_players WHERE expires_at <= ?').bind(cutoff),
      env.DB.prepare('DELETE FROM rate_reports WHERE updated_at <= ?').bind(cutoff - RATE_TTL),
    ]));
  },
};

