# VCV Rack ↔ 4ms MetaModule Sync

Keeps your VCV Rack plugin library in sync with the modules compatible with the [4ms MetaModule](https://metamodule.4ms.info) hardware Eurorack module.

Supports **Linux**, **macOS**, and **Windows**.

## How it works

1. Reads your VCV Rack login token from `settings.json`
2. Fetches the latest plugin versions from the VCV Library API
3. Downloads any missing or outdated MetaModule-compatible plugins directly to your Rack plugins folder
4. On next launch, VCV Rack auto-extracts and loads them

## Quick start

### Linux / macOS

```bash
# One-time install (sets up weekly auto-sync)
bash install-linux.sh

# Manual sync anytime
python3 sync.py

# Dry run — see what would change without downloading
python3 sync.py --check
```

### Windows (PowerShell)

```powershell
# One-time install (registers weekly Task Scheduler job)
.\install-windows.ps1

# Manual sync anytime
.\sync.ps1

# Dry run
.\sync.ps1 -Check
```

## Requirements

- **VCV Rack 2** installed and logged in (Library menu → Log in)
- **Python 3.7+** (Linux/macOS/Windows) — only uses standard library
- No extra dependencies needed

## Plugin list

64 plugins compatible with MetaModule are synced. To see the full list:

```bash
python3 sync.py --list
```

Source: [metamodule.4ms.info/plugins](https://metamodule.4ms.info/plugins)

## File locations

| Platform | VCV Rack settings | Plugins folder |
|---|---|---|
| Linux | `~/.local/share/Rack2/settings.json` | `~/.local/share/Rack2/plugins-lin-x64/` |
| macOS | `~/Documents/Rack2/settings.json` | `~/Documents/Rack2/plugins-mac-x64/` |
| Windows | `%APPDATA%\Rack2\settings.json` | `%APPDATA%\Rack2\plugins-win-x64\` |

## Auto-sync schedule

| Platform | Method | Schedule |
|---|---|---|
| Linux | systemd user timer | Weekly (Monday) |
| macOS | launchd plist | Weekly (Monday 9am) |
| Windows | Task Scheduler | Weekly (Monday 9am) |

## Updating the plugin list

The MetaModule-compatible plugin list is hardcoded in `sync.py` and `sync.ps1`.  
When 4ms adds new plugins to [their page](https://metamodule.4ms.info/plugins), update the `MM_SLUGS` list in both files and commit.
