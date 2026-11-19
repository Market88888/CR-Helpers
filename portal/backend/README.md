# PC Stats portal backend

The Cloudflare Worker serves the static portal and a small D1-backed API. The online list is opt-in: the client must send `consent: true` on every heartbeat. Online rows expire after two minutes. `/api/optout` removes the user's active row and rate reports. Public APIs never return the internal hashed client ID.

The client companion is `PCStatsSiteLink.lua`. It is off by default. A player must type `/pcstatsshare on`; `/pcstatsshare off` removes the entry. It sends only the current nickname and server address. Crash logs, chat messages, credentials, and visit history are not uploaded. The client ID is a random local value used only to refresh and delete the opted-in row; the backend stores only its SHA-256 digest.

## Deploy

1. Install Node.js and Wrangler, then run `npx wrangler login`.
2. From this directory, create the database:

   ```sh
   npx wrangler d1 create pcstats-presence
   ```

3. Put the returned database ID into `wrangler.toml` in place of `REPLACE_WITH_ID_FROM_WRANGLER_D1_CREATE`.
4. Create the tables:

   ```sh
   npx wrangler d1 execute pcstats-presence --remote --file=./schema.sql
   ```

5. Deploy the site and API:

   ```sh
   npx wrangler deploy
   ```

6. Replace `API_BASE` near the top of `PCStatsSiteLink.lua` with the resulting `https://pcstats-portal.<account-subdomain>.workers.dev` URL, then publish that client file with the PC Stats release.

## Endpoints

- `GET /api/players` — active opted-in users, with nickname and server only.
- `POST /api/heartbeat` — requires `consent: true`, a local `clientId`, nickname, and server. Optional `rates` accepts `vc`, `btc`, `az`, `aarp`, and `asc` values.
- `POST /api/optout` — deletes this client's online row and rate reports.
- `GET /api/rates` — returns the median of recent reports by server, with the number of reporting clients.

Rate reports are retained for up to 24 hours and are only accepted with an opted-in heartbeat. Online rows are removed by the minute cleanup job or when the player opts out. The current client sends presence only; rate fields are an API extension for a later client integration.

