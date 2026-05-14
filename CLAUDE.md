# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this does

Syncs VCV Rack 2 plugin library to include all plugins compatible with the [4ms MetaModule](https://metamodule.4ms.info) hardware Eurorack module. Reads the VCV Rack login token from `settings.json` (or `VCV_TOKEN` env var), fetches the VCV Library API manifests, and downloads missing/outdated `.vcvplugin` files into the Rack plugins folder. VCV Rack auto-extracts them on next launch.

## Commands

### Linux / macOS
```bash
python3 sync.py           # sync all MetaModule plugins
python3 sync.py --check   # dry run -- show what would change
python3 sync.py --list    # print all MM-compatible slugs
bash install-linux.sh     # one-time: register weekly auto-sync
```

### Windows (PowerShell -- must use -ExecutionPolicy Bypass)
```powershell
powershell -ExecutionPolicy Bypass -File .\sync.ps1
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check
.\install-windows.ps1     # one-time: register weekly Task Scheduler job (requires Admin)
```

## Architecture

Two parallel implementations of the same logic -- keep `MM_SLUGS` list in sync between both files when updating:

| File | Platform | Notes |
|------|----------|-------|
| `sync.py` | Linux / macOS / Windows | Python stdlib only, auto-detects arch and platform paths |
| `sync.ps1` | Windows primary | Defaults to `win-x64`, handles LocalAppData vs AppData |
| `install-linux.sh` | Linux -> systemd timer / macOS -> launchd plist | |
| `install-windows.ps1` | Windows Task Scheduler | Runs sync.ps1 weekly Monday 9am, requires Admin |

### VCV API flow
1. `GET /library/manifests?version=2` -- public endpoint, no auth needed
2. Compare against `plugin.json` inside each installed plugin folder to detect outdated
3. `GET /download?slug=X&version=Y&arch=Z` -- download `.vcvplugin` bundle, requires `Cookie: token=<value>`
4. Auth token read from `settings.json` -> `.token` field, or `VCV_TOKEN` env var

### Token scope limitation
The token stored by VCV Rack desktop (20 chars) **only allows downloads of already-subscribed plugins**. `POST /plugins` (subscribe) returns 401 -- requires a full web session token. Plugins must be subscribed first at https://library.vcvrack.com before they can be downloaded via API.

### Favorites
`--favorites` / `-Favorites` patches `settings.json -> moduleInfos[pluginSlug][moduleSlug].favorite = true`. VCV Rack reads this on startup to populate the browser favorites filter. **VCV Rack must be closed** before running -- it overwrites settings.json on exit.

Exact per-module compatibility data scraped live from `https://metamodule.4ms.info/modulefinder`. Scraped slugs are validated against `MM_SLUGS_SET` allowlist before use.

## Updating the plugin list

When 4ms adds new plugins at https://metamodule.4ms.info/modulefinder, update `MM_SLUGS` in **both** `sync.py` and `sync.ps1`. The `MM_PAID` dict in both files tracks plugins that require purchase.

## Security notes

- Downloads written to `.tmp` first, validated as ZIP (magic bytes + structure), then atomically renamed -- corrupt/partial downloads never reach the plugin folder
- `settings.json` backed up (rotating, keeps 5) before favorites write; written atomically via `.tmp`
- Scraped plugin slugs from modulefinder validated against local `MM_SLUGS_SET` allowlist (H4)
- Error messages sanitize token from URLs before printing (M6)
- Manifests endpoint called without auth token (public, L3)
- `VCV_TOKEN` env var preferred over reading token from disk
