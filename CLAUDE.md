# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this does

Syncs VCV Rack 2 plugin library to include all plugins compatible with the [4ms MetaModule](https://metamodule.4ms.info) hardware Eurorack module. Reads the VCV Rack login token from `settings.json`, fetches the VCV Library API manifests, and downloads missing/outdated `.vcvplugin` files into the Rack plugins folder. VCV Rack auto-extracts them on next launch.

## Commands

### Linux / macOS
```bash
python3 sync.py           # sync all MetaModule plugins
python3 sync.py --check   # dry run — show what would change
python3 sync.py --list    # print all 64 MM-compatible slugs
bash install-linux.sh     # one-time: register weekly auto-sync
```

### Windows (PowerShell — must use -ExecutionPolicy Bypass)
```powershell
powershell -ExecutionPolicy Bypass -File .\sync.ps1
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check
.\install-windows.ps1     # one-time: register weekly Task Scheduler job
```

> **Windows quirk:** VCV Rack stores data in `%LOCALAPPDATA%\Rack2` (not `%APPDATA%\Rack2` as README says). `sync.ps1` already handles this with a `Test-Path` check. `sync.py` still hardcodes `%APPDATA%` — fix `get_rack_paths()` if using Python on Windows.

## Architecture

Two parallel implementations of the same logic — keep `MM_SLUGS` list in sync between both files when updating:

| File | Platform | Notes |
|------|----------|-------|
| `sync.py` | Linux / macOS (+ Windows fallback) | Python stdlib only, auto-detects arch |
| `sync.ps1` | Windows primary | Defaults to `win-x64`, LocalAppData fix applied |
| `install-linux.sh` | Linux → systemd timer / macOS → launchd plist | |
| `install-windows.ps1` | Windows Task Scheduler | Runs sync.ps1 weekly Monday 9am |

### VCV API flow
1. `GET /library/manifests?version=2` — returns all plugin manifests with version + arches map
2. Compare against `plugin.json` inside each installed plugin folder to detect outdated
3. `GET /download?slug=X&version=Y&arch=Z` — download `.vcvplugin` bundle
4. Auth: `Cookie: token=<value>` header (read from `settings.json` → `.token` field)

### Token scope limitation
The token stored by VCV Rack desktop (20 chars) **only allows downloads of already-subscribed plugins**. `POST /plugins` (subscribe) returns 401 with this token — it requires a full web session token. Plugins must be subscribed first at https://library.vcvrack.com before they can be downloaded via API.

## Updating the plugin list

When 4ms adds new plugins at https://metamodule.4ms.info/plugins, update `MM_SLUGS` in **both** `sync.py` and `sync.ps1`.
