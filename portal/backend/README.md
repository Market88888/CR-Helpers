# PC Stats portal backend

The `pcstats-portal` Cloudflare Worker provides the D1-backed API. Static files are deployed separately as `pcstats-site`. The online list is opt-in: the client must send `consent: true` on every heartbeat. Online rows expire after two minutes. `/api/optout` removes the user's active row and rate reports. Public APIs never return the internal hashed client ID.

The client companion is `PCStatsSiteLink.lua`. It is off by default. A player must type `/pcstatsshare on`; `/pcstatsshare off` removes the entry. It sends the current nickname, server address, and five saved course values read from `settings.ini`. It does not read or upload crash logs, chat messages, credentials, balance, or visit history. The client ID is a random local value used only to refresh and delete the opted-in row; the backend stores only its SHA-256 digest.

## Deploy

1. Create the D1 database `pcstats-presence` and run `schema.sql` from its Console.
2. Bind it to Worker `pcstats-portal` as `DB`, set `SITE_ORIGIN` to `https://pcstats-site.arizonam30.workers.dev`, and add cron `*/1 * * * *`.
3. Upload the contents of `site/` as static site Worker `pcstats-site`.
4. Install `PCStatsSiteLink.lua` next to `PCStats.lua`. Sharing is off until `/pcstatsshare on`.

For command-line deployments, install Node.js and Wrangler, then run `npx wrangler login`. The database ID is already in `wrangler.toml`:

```sh
npx wrangler d1 execute pcstats-presence --remote --file=./schema.sql
npx wrangler deploy
```

Deploy `site/` separately with Cloudflare Workers static assets or Pages.

## Endpoints

- `GET /api/players` — active opted-in users, with nickname and server only.
- `POST /api/heartbeat` — requires `consent: true`, a local `clientId`, nickname, and server. Optional `rates` accepts `vc`, `btc`, `az`, `aarp`, and `asc` values.
- `POST /api/optout` — deletes this client's online row and rate reports.
- `GET /api/rates` — returns the median of recent reports by server, with the number of reporting clients.

Rate reports are retained for up to 24 hours and are only accepted with an opted-in heartbeat. Online rows are removed by the minute cleanup job or when the player opts out. The worker groups recent reports by server and returns the median, reducing the effect of one incorrect report.

