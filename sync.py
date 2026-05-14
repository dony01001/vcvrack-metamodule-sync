#!/usr/bin/env python3
"""
sync.py -- VCV Rack <-> 4ms MetaModule plugin sync
Works on Linux, macOS, and Windows.

Usage:
    python3 sync.py                # sync all free MetaModule-compatible plugins
    python3 sync.py --check        # dry run: show what would change
    python3 sync.py --list         # print full plugin list
    python3 sync.py --subscribe    # open browser tabs for unsubscribed plugins
    python3 sync.py --favorites    # add MM modules to VCV Rack favorites
    python3 sync.py --include-paid # also include paid plugins ($)
"""

import argparse
import json
import os
import platform
import re
import shutil
import sys
import urllib.request
import urllib.error
import webbrowser
from datetime import datetime
from pathlib import Path

# -- MetaModule compatible plugin slugs ----------------------------------------
# Source: https://metamodule.4ms.info/modulefinder
MM_SLUGS = [
    "21kHz",
    "4ms-ProducerPack",
    "4ms-ROMplers",
    "4ms-XOXDrums",
    "4msCompany",
    "Airwin2Rack",
    "AlliewayAudio_Freebies",
    "AmalgamatedHarmonics",
    "AudibleInstruments",
    "Autinn",
    "Bastl",
    "Befaco",
    "Bidoo",
    "BlackNoiseModular",
    "Bogaudio",
    "CVfunk",
    "Cella",
    "ChowDSP",
    "CosineKitty-Sapphire",
    "CountModula",
    "CuteLab",
    "DrumKit",
    "ESeries",
    "FehlerFabrik-Suite",
    "Fundamental",
    "Geodesics",
    "HetrickCV",
    "ImpromptuModular",
    "InfrasonicAudio",
    "JW-Modules",
    "KRTPluginA",
    "MADZINE",
    "MSM",
    "MUS-X",
    "MockbaModular",
    "Moffenzeef",
    "NANOModules",
    "NOI",
    "NonlinearCircuits",
    "Nozoid",
    "Ondas",
    "OrangeLine",
    "PathSet",
    "RPJ",
    "RebelTech",
    "Rigatoni",
    "SanguineMonsters",
    "SanguineMutants",
    "SeasideModular",
    "SickoCV",
    "SignalFunctionSet",
    "SonusModular",
    "StellareModular",
    "StellareModular-CreativeSuite",
    "StudioSixPlusOne",
    "UnfilteredVolume1",
    "UnfilteredVolume2",
    "Valley",
    "Venom",
    "WordGenerator",
    "dBiz",
    "eightfold",
    "kocmoc",
    "mscHack",
    "nullpath",
    "squinkylabs-plug1",
    "vanTies",
    "voxglitch",
]

# Paid plugins -- require purchase on library.vcvrack.com before download
MM_PAID = {
    "StellareModular-CreativeSuite",  # $25 -- https://library.vcvrack.com/StellareModular-CreativeSuite
    "UnfilteredVolume1",              # $25 -- https://library.vcvrack.com/UnfilteredVolume1
    "UnfilteredVolume2",              # $30 -- https://library.vcvrack.com/UnfilteredVolume2
}

MODULEFINDER_URL = "https://metamodule.4ms.info/modulefinder"
API = "https://api.vcvrack.com"


# -- Platform helpers ----------------------------------------------------------

def get_platform_info():
    sys_name = platform.system()
    machine  = platform.machine().lower()
    os_key   = {"Windows": "win", "Darwin": "mac"}.get(sys_name, "lin")
    cpu_key  = "arm64" if ("arm" in machine or "aarch64" in machine) else "x64"
    return f"{os_key}-{cpu_key}"


def get_rack_paths(arch: str):
    sys_name = platform.system()
    if sys_name == "Windows":
        local   = Path(os.environ.get("LOCALAPPDATA", ""))
        roaming = Path(os.environ.get("APPDATA", ""))
        base = local / "Rack2" if (local / "Rack2" / "settings.json").exists() else roaming / "Rack2"
    elif sys_name == "Darwin":
        base = Path.home() / "Documents" / "Rack2"
    else:
        base = Path.home() / ".local" / "share" / "Rack2"
    return {
        "settings":  base / "settings.json",
        "plugins":   base / f"plugins-{arch}",
        "favorites": base / "favoriteModules.json",
    }


def read_token(settings_path: Path) -> str:
    if not settings_path.exists():
        return ""
    try:
        with open(settings_path) as f:
            return json.load(f).get("token", "")
    except Exception:
        return ""


# -- Network helpers -----------------------------------------------------------

def api_get(path: str, token: str = "") -> dict:
    url = f"{API}{path}"
    req = urllib.request.Request(url)
    if token:
        req.add_header("Cookie", f"token={token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} fetching {url}")
    except Exception as e:
        raise RuntimeError(f"Request failed: {e}")


def fetch_modulefinder() -> dict[str, list[str]]:
    """
    Scrape metamodule.4ms.info/modulefinder and return
    {plugin_slug: [module_slug, ...]} for every MM-compatible module.
    Falls back to empty dict on failure.
    """
    try:
        req = urllib.request.Request(
            MODULEFINDER_URL,
            headers={"User-Agent": "vcvrack-metamodule-sync/2.0"}
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            html = r.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  WARNING: could not fetch modulefinder ({e})")
        return {}

    # Extract links like https://library.vcvrack.com/PluginSlug/ModuleSlug
    pattern = r'https://library\.vcvrack\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)'
    result: dict[str, list[str]] = {}
    for plugin_slug, module_slug in re.findall(pattern, html):
        result.setdefault(plugin_slug, [])
        if module_slug not in result[plugin_slug]:
            result[plugin_slug].append(module_slug)

    return result


def download_plugin(slug: str, version: str, arch: str, token: str, dest: Path):
    """Returns (ok: bool, needs_subscribe: bool)"""
    url = f"{API}/download?slug={slug}&version={version}&arch={arch}"
    req = urllib.request.Request(url)
    if token:
        req.add_header("Cookie", f"token={token}")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        if len(data) < 1000:
            return False, False
        dest.write_bytes(data)
        return True, False
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode()
        except Exception:
            body = ""
        if "not owned" in body or "not subscribed" in body or "downloadable" in body:
            return False, True
        return False, False
    except Exception:
        return False, False


def get_installed_version(plugin_dir: Path, slug: str) -> str:
    pjson = plugin_dir / slug / "plugin.json"
    if not pjson.exists():
        return ""
    try:
        with open(pjson) as f:
            return json.load(f).get("version", "")
    except Exception:
        return ""


# -- Favorites -----------------------------------------------------------------

def update_favorites(plugin_dir: Path, favorites_path: Path):
    """
    Merge MetaModule-compatible modules into favoriteModules.json.
    Uses metamodule.4ms.info/modulefinder for the exact list of compatible
    modules (not all modules in a plugin, only those confirmed by 4ms).
    Falls back to plugin.json if modulefinder is unreachable.
    """
    # Backup existing file
    fav = {}
    if favorites_path.exists():
        ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = favorites_path.with_name(f"favoriteModules.backup.{ts}.json")
        shutil.copy2(favorites_path, backup)
        print(f"  Backup saved: {backup.name}")
        try:
            with open(favorites_path) as f:
                fav = json.load(f)
        except Exception:
            fav = {}

    # Fetch exact MM module list from modulefinder
    print("  Fetching module list from metamodule.4ms.info/modulefinder...")
    mm_modules = fetch_modulefinder()

    if mm_modules:
        print(f"  Found {sum(len(v) for v in mm_modules.values())} MM-compatible modules across {len(mm_modules)} plugins")
        source = "modulefinder"
    else:
        print("  Falling back to local plugin.json (modulefinder unreachable)")
        source = "local"

    added_mods = 0
    skipped    = 0

    for slug in MM_SLUGS:
        if mm_modules:
            # Use exact list from modulefinder
            module_slugs = mm_modules.get(slug, [])
            if not module_slugs:
                print(f"  SKIP {slug:<44} not in modulefinder")
                skipped += 1
                continue
        else:
            # Fallback: all modules from installed plugin.json
            pjson = plugin_dir / slug / "plugin.json"
            if not pjson.exists():
                print(f"  SKIP {slug:<44} not installed")
                skipped += 1
                continue
            try:
                with open(pjson) as f:
                    meta = json.load(f)
                module_slugs = [m["slug"] for m in meta.get("modules", [])]
            except Exception:
                print(f"  SKIP {slug:<44} could not read plugin.json")
                skipped += 1
                continue

        # Replace MM plugin entry with exact modulefinder data (not merge)
        # so stale modules from old plugin.json runs don't accumulate
        old_count  = len(fav.get(slug, []))
        fav[slug]  = module_slugs
        added_mods += len(module_slugs)
        print(f"  FAV  {slug:<44} {len(module_slugs)} modules (was {old_count})  [{source}]")

    with open(favorites_path, "w") as f:
        json.dump(fav, f, indent=2)

    print(f"\n+{added_mods} modules added to favorites. {skipped} plugins skipped.")
    print("Restart VCV Rack and filter by Favorites to see MetaModule-compatible modules.")


# -- Main ----------------------------------------------------------------------

def confirm(prompt: str) -> bool:
    try:
        return input(f"{prompt} [y/N] ").strip().lower() == "y"
    except (EOFError, KeyboardInterrupt):
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Sync VCV Rack plugins with those compatible with the 4ms MetaModule.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  python3 sync.py                  sync all free MetaModule plugins
  python3 sync.py --check          dry run: show what would change
  python3 sync.py --subscribe      open browser to subscribe missing plugins
  python3 sync.py --favorites      add MM modules to VCV Rack favorites
  python3 sync.py --include-paid   also include paid plugins
        """,
    )
    parser.add_argument("--check",        action="store_true", help="Dry run -- show what would change")
    parser.add_argument("--list",         action="store_true", help="Print MetaModule plugin list and exit")
    parser.add_argument("--subscribe",    action="store_true", help="Open browser tabs for plugins needing subscribe")
    parser.add_argument("--favorites",    action="store_true", help="Add MM modules to VCV Rack favorites")
    parser.add_argument("--include-paid", action="store_true", help="Include paid plugins (skipped by default)")
    parser.add_argument("--token",        default="", help="Override VCV token")
    parser.add_argument("--arch",         default="", help="Override platform arch (e.g. lin-x64)")
    args = parser.parse_args()

    active_slugs = MM_SLUGS if args.include_paid else [s for s in MM_SLUGS if s not in MM_PAID]

    if args.list:
        for s in sorted(active_slugs):
            paid = " [$]" if s in MM_PAID else ""
            print(f"{s}{paid}")
        return

    arch  = args.arch or get_platform_info()
    paths = get_rack_paths(arch)
    token = args.token or read_token(paths["settings"])

    if not token:
        print("ERROR: No VCV token found.")
        print("  Open VCV Rack and log in via Library menu, then re-run.")
        print(f"  Expected: {paths['settings']}")
        sys.exit(1)

    plugin_dir = paths["plugins"]
    plugin_dir.mkdir(parents=True, exist_ok=True)

    paid_note = (" (including paid)" if args.include_paid
                 else f" (+ {len(MM_PAID)} paid skipped, use --include-paid)")
    print(f"Platform : {arch}")
    print(f"Plugins  : {plugin_dir}")
    print(f"Mode     : {'DRY RUN' if args.check else 'SYNC'}")
    print(f"Syncing  : {len(active_slugs)} plugins{paid_note}")
    print()

    print("Fetching plugin versions from VCV Library...")
    try:
        manifests_data = api_get("/library/manifests?version=2", token)
    except RuntimeError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    manifests    = manifests_data.get("manifests", {})
    downloaded   = 0
    skipped      = 0
    failed       = 0
    to_subscribe = []

    for slug in active_slugs:
        manifest = manifests.get(slug, {})
        version  = manifest.get("version", "")
        arches   = manifest.get("arches", {})

        if not version or not arches.get(arch):
            print(f"  SKIP {slug:<44} not available for {arch}")
            skipped += 1
            continue

        installed = get_installed_version(plugin_dir, slug)
        if installed == version:
            print(f"  OK   {slug:<44} {version}")
            skipped += 1
            continue

        label = (f"UPD  {slug:<44} {installed} -> {version}"
                 if installed else f"GET  {slug:<44} {version}")

        if args.check:
            print(f"  {label}  [dry run]")
            continue

        print(f"  {label}", end="", flush=True)
        out = plugin_dir / f"{slug}-{version}-{arch}.vcvplugin"
        ok, needs_sub = download_plugin(slug, version, arch, token, out)

        if ok:
            print("  OK")
            downloaded += 1
        elif needs_sub:
            print("  NEEDS SUBSCRIBE")
            to_subscribe.append(slug)
            out.unlink(missing_ok=True)
        else:
            print("  FAILED")
            out.unlink(missing_ok=True)
            failed += 1

    print()
    print(f"Downloaded: {downloaded}  Skipped: {skipped}  Failed: {failed}  Need subscribe: {len(to_subscribe)}")

    # -- Subscribe list --------------------------------------------------------
    if to_subscribe:
        print()
        print("Subscribe these plugins for free at library.vcvrack.com:")
        for slug in to_subscribe:
            print(f"  https://library.vcvrack.com/{slug}")

        if args.subscribe:
            print()
            if confirm(f"Open {len(to_subscribe)} browser tabs?"):
                for slug in to_subscribe:
                    webbrowser.open(f"https://library.vcvrack.com/{slug}")
                print("Click Subscribe on each tab, then re-run sync.")
        else:
            print("\nTip: run with --subscribe to open all URLs in browser automatically.")

    if downloaded > 0:
        print("\nRestart VCV Rack to load new plugins.")

    # -- Favorites -------------------------------------------------------------
    if args.favorites:
        print("\nUpdating VCV Rack favorites with MetaModule modules...")
        update_favorites(plugin_dir, paths["favorites"])


if __name__ == "__main__":
    main()
