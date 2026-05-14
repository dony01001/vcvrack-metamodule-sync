# VCV Rack <-> 4ms MetaModule Sync

Keeps your VCV Rack plugin library in sync with the modules compatible with the [4ms MetaModule](https://metamodule.4ms.info) hardware Eurorack module.

Supports **Linux**, **macOS**, and **Windows**.

## How it works

1. Reads your VCV Rack login token from `settings.json` (or `VCV_TOKEN` env var)
2. Fetches the latest plugin versions from the VCV Library API
3. Downloads any missing or outdated MetaModule-compatible plugins to your Rack plugins folder
4. On next launch, VCV Rack auto-extracts and loads them

## Quick start

### Linux / macOS

```bash
# Manual sync
python3 sync.py

# Dry run -- see what would change without downloading
python3 sync.py --check

# One-time install (sets up weekly auto-sync)
bash install-linux.sh
```

### Windows (PowerShell)

```powershell
# Manual sync
powershell -ExecutionPolicy Bypass -File .\sync.ps1

# Dry run
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check

# One-time install (registers weekly Task Scheduler job -- requires Admin)
.\install-windows.ps1
```

## Requirements

- **VCV Rack 2** installed and logged in (Library menu -> Log in)
- **Python 3.7+** for Linux/macOS -- standard library only, no pip installs needed

## Subscribing to plugins

VCV Library requires you to **Subscribe** (free) to a plugin before downloading it. If the sync reports plugins that need subscribing, run:

```bash
# Linux / macOS -- opens browser tabs automatically
python3 sync.py --subscribe

# Windows
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Subscribe
```

This prints a list of URLs and offers to open them in your browser. Click **Subscribe** on each page, then re-run sync.

## Paid plugins

Three MetaModule-compatible plugins are **paid** and are skipped by default:

| Plugin | Price | Link |
|--------|-------|------|
| StellareModular-CreativeSuite | $25 | https://library.vcvrack.com/StellareModular-CreativeSuite |
| UnfilteredVolume1 | $25 | https://library.vcvrack.com/UnfilteredVolume1 |
| UnfilteredVolume2 | $30 | https://library.vcvrack.com/UnfilteredVolume2 |

To include them after purchasing:

```bash
python3 sync.py --include-paid        # Linux / macOS
.\sync.ps1 -IncludePaid               # Windows
```

## Mark MetaModule modules as favorites in VCV Rack

Add all MetaModule-compatible modules to your VCV Rack favorites list so you can filter the module browser to only show what runs on MetaModule.

> **Important:** Close VCV Rack completely before running this. Changes to `settings.json` are overwritten when Rack exits.

```bash
python3 sync.py --favorites           # Linux / macOS
.\sync.ps1 -Favorites                 # Windows
```

Then in VCV Rack, open the module browser and enable the **Favorites** filter.

## Combining flags

```bash
# Sync + open subscribe tabs + update favorites in one run
python3 sync.py --subscribe --favorites

# Windows equivalent
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Subscribe -Favorites
```

## Plugin list

67 plugins compatible with MetaModule are tracked. To see the full list:

```bash
python3 sync.py --list
```

Source: [metamodule.4ms.info/modulefinder](https://metamodule.4ms.info/modulefinder)

## Authentication

The script reads your VCV Rack token automatically from `settings.json`. You can also set it via environment variable to avoid reading from disk:

```bash
export VCV_TOKEN=your_token_here   # Linux / macOS
$env:VCV_TOKEN = "your_token_here" # Windows PowerShell
```

## File locations

| Platform | VCV Rack settings | Plugins folder |
|----------|-------------------|----------------|
| Linux    | `~/.local/share/Rack2/settings.json` | `~/.local/share/Rack2/plugins-lin-x64/` |
| macOS    | `~/Documents/Rack2/settings.json` | `~/Documents/Rack2/plugins-mac-x64/` |
| Windows  | `%LOCALAPPDATA%\Rack2\settings.json` | `%LOCALAPPDATA%\Rack2\plugins-win-x64\` |

## Auto-sync schedule

| Platform | Method | Schedule |
|----------|--------|----------|
| Linux    | systemd user timer | Weekly (Monday) |
| macOS    | launchd plist | Weekly (Monday 9am) |
| Windows  | Task Scheduler | Weekly (Monday 9am) |

The Windows installer (`install-windows.ps1`) requires Administrator privileges to register the scheduled task.

## Updating the plugin list

The MetaModule-compatible plugin list is hardcoded in `sync.py` and `sync.ps1`.
When 4ms adds new plugins to [their page](https://metamodule.4ms.info/modulefinder), update `MM_SLUGS` in both files and commit.
