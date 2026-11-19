# PC Stats portal

Responsive website for PC Stats with an opt-in online list, per-server rates, and a link to the official GitHub release.

## Privacy behavior

- Sharing is off by default. A player enables it by typing `/pcstatsshare on` in the game.
- The companion script displays what it shares: the current nickname, server address, and saved currency rates while the player is online.
- `/pcstatsshare off` asks the backend to delete that player's presence and rate reports.
- Online rows expire after two minutes without a heartbeat. The site never receives crash logs, chat text, account passwords, or code-change reports.
- A random local ID is used only to refresh or remove the opted-in row. The backend hashes it and does not return it publicly.

## Deploy

The portal is deployed as a static-assets Worker at `https://pcstats-site.arizonam30.workers.dev`. Its API runs in `pcstats-portal` and stores opted-in presence and rate reports in Cloudflare D1 (`pcstats-presence`). The website calls the API through the `api-base` setting in `site/index.html`.

The client helper is a separate MoonLoader file. Install it beside `PCStats.lua`; sharing stays off until a player types `/pcstatsshare on`. The website shows no names until a player opts in and the helper is installed.

## What's connected

- Online status API and public online list.
- Rates API takes fresh per-server observations from opted-in clients and displays their median.
- Version card reads `manifest.json` from this repository.

The companion helper reads only the five course values from `settings.ini` and sends them with the opted-in heartbeat. It does not read or upload tax logs, crash logs, chat, balance, or other settings.

