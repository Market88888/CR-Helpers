(() => {
  const API = (document.querySelector('meta[name="api-base"]')?.content || '').trim().replace(/\/$/, '') || window.location.origin;
  const REPO = 'https://github.com/Market88888/CR-Helpers';
  const state = { players: [], rates: [], page: 'home' };
  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const dateTime = (value) => {
    const d = value ? new Date(value) : null;
    return d && !Number.isNaN(d.getTime()) ? d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—';
  };
  const pageError = 'Сервер сайта ещё не подключён. Проверь адрес API в index.html после настройки backend.';

  function showPage(name) {
    state.page = name;
    document.querySelectorAll('main, .page').forEach((el) => el.classList.toggle('hidden', el.id !== name));
    document.querySelectorAll('.nav-link').forEach((el) => el.classList.toggle('active', el.dataset.page === name));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
  document.querySelectorAll('[data-page]').forEach((el) => el.addEventListener('click', () => showPage(el.dataset.page)));
  document.querySelectorAll('[data-go]').forEach((el) => el.addEventListener('click', () => showPage(el.dataset.go)));

  function playerCard(p) {
    const nick = esc(p.nickname);
    const server = esc(p.server);
    return `<article class="player-card"><div class="player-card-top"><span class="player-name">${nick}</span><i class="online-indicator" title="Онлайн"></i></div><div class="player-server">${server}</div></article>`;
  }
  function renderPlayers(filter = '') {
    const q = filter.trim().toLocaleLowerCase('ru');
    const rows = state.players.filter((p) => `${p.nickname} ${p.server}`.toLocaleLowerCase('ru').includes(q));
    const preview = $('player-preview');
    if (preview) preview.innerHTML = rows.slice(0, 6).map(playerCard).join('') || `<div class="empty">${state.players.length ? 'Совпадений не найдено.' : 'Пока нет игроков, включивших показ статуса.'}</div>`;
    const list = $('players-list');
    if (list) list.innerHTML = rows.map(playerCard).join('') || '';
    const empty = $('players-empty');
    if (empty) { empty.textContent = rows.length ? '' : (state.players.length ? 'По запросу ничего не найдено.' : 'Сейчас нет игроков с включённым публичным статусом.'); empty.classList.toggle('hidden', rows.length > 0); }
    if ($('players-summary')) $('players-summary').textContent = `${rows.length} ${rows.length === 1 ? 'игрок' : 'игроков'} в списке`;
    if ($('hero-count')) $('hero-count').textContent = String(state.players.length);
    if ($('stat-online')) $('stat-online').textContent = String(state.players.length);
    if ($('stat-servers')) $('stat-servers').textContent = String(new Set(state.players.map((p) => p.server)).size);
    if ($('online-pill')) $('online-pill').textContent = `${state.players.length} онлайн`;
    if ($('players-live')) $('players-live').textContent = `${state.players.length} онлайн`;
  }
  function rateRows(filter = '', full = false) {
    const q = filter.trim().toLocaleLowerCase('ru');
    const data = state.rates.filter((r) => String(r.server).toLocaleLowerCase('ru').includes(q));
    const names = full ? ['server','vc','btc','az','aarp','asc','updated'] : ['server','vc','btc','az','aarp','updated'];
    const body = data.map((r) => `<tr><td class="server-name">${esc(r.server)}</td><td class="rate-value">${esc(r.vc ?? '—')}</td><td class="rate-value">${esc(r.btc ?? '—')}</td><td class="rate-value">${esc(r.az ?? '—')}</td><td class="rate-value">${esc(r.aarp ?? '—')}</td>${full ? `<td class="rate-value">${esc(r.asc ?? '—')}</td>` : ''}<td>${esc(dateTime(r.updated))}</td></tr>`).join('');
    const target = $(full ? 'rates-list' : 'rates-preview');
    if (target) target.innerHTML = body || `<tr><td colspan="${names.length}" class="muted">${data.length ? '' : 'Курсы ещё не опубликованы.'}</td></tr>`;
    const empty = $('rates-empty');
    if (full && empty) { empty.textContent = data.length ? '' : 'Пока нет опубликованных курсов. Они появятся после подключения источника данных.'; empty.classList.toggle('hidden', data.length > 0); }
  }
  async function loadPlayers() {
    if (!API || API.includes('example.workers.dev')) throw new Error(pageError);
    const r = await fetch(`${API}/api/players`, { headers: { accept: 'application/json' }, cache: 'no-store' });
    if (!r.ok) throw new Error(`Ответ сервера: ${r.status}`);
    const d = await r.json();
    state.players = Array.isArray(d.players) ? d.players : [];
    renderPlayers($('player-search')?.value || '');
    if ($('updated-at')) $('updated-at').textContent = `обновлено ${dateTime(d.updatedAt)}`;
  }
  async function loadRates() {
    if (!API || API.includes('example.workers.dev')) throw new Error(pageError);
    const r = await fetch(`${API}/api/rates`, { headers: { accept: 'application/json' }, cache: 'no-store' });
    if (!r.ok) throw new Error(`Ответ сервера: ${r.status}`);
    const d = await r.json();
    state.rates = Array.isArray(d.rates) ? d.rates : [];
    rateRows($('rate-search')?.value || '', true);
    rateRows('', false);
  }
  async function loadRelease() {
    try {
      const r = await fetch('https://raw.githubusercontent.com/Market88888/CR-Helpers/main/manifest.json', { cache: 'no-store' });
      if (!r.ok) throw new Error('GitHub недоступен');
      const d = await r.json();
      const version = d.version || d.latest || 'доступна на GitHub';
      if ($('stat-version')) $('stat-version').textContent = version;
      if ($('release-version')) $('release-version').textContent = `PC Stats ${version}`;
      if ($('release-description')) $('release-description').textContent = 'Официальная версия и файл скрипта доступны в репозитории.';
    } catch (_) {
      if ($('stat-version')) $('stat-version').textContent = 'GitHub';
      if ($('release-version')) $('release-version').textContent = 'Репозиторий PC Stats';
      if ($('release-description')) $('release-description').textContent = 'Открой GitHub, чтобы посмотреть текущую версию и историю изменений.';
    }
  }
  function showLoadError(error) {
    const message = esc(error?.message || pageError);
    if ($('player-preview')) $('player-preview').innerHTML = `<div class="empty">${message}</div>`;
    if ($('players-list')) $('players-list').innerHTML = '';
    if ($('players-empty')) { $('players-empty').textContent = message; $('players-empty').classList.remove('hidden'); }
    if ($('online-pill')) $('online-pill').textContent = 'API недоступен';
    if ($('players-live')) $('players-live').textContent = 'API недоступен';
  }
  $('player-search')?.addEventListener('input', (e) => renderPlayers(e.target.value));
  $('rate-search')?.addEventListener('input', (e) => rateRows(e.target.value, true));
  $('refresh-players')?.addEventListener('click', () => loadPlayers().catch(showLoadError));
  $('refresh-rates')?.addEventListener('click', () => loadRates().catch(() => {}));
  $('year').textContent = new Date().getFullYear();
  document.querySelectorAll('.year').forEach((el) => { el.textContent = new Date().getFullYear(); });
  loadRelease();
  loadPlayers().catch(showLoadError);
  loadRates().catch(() => rateRows('', true));
  window.setInterval(() => loadPlayers().catch(() => {}), 30000);
  void REPO;
})();

