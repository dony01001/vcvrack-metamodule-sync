#!/usr/bin/env python3
"""
sync.py — VCV Rack ↔ 4ms MetaModule plugin sync
Works on Linux, macOS, and Windows.

Usage:
    python3 sync.py            # sync all MetaModule-compatible plugins
    python3 sync.py --check    # show what would change, don't download
    python3 sync.py --list     # print full MetaModule plugin list
"""

import argparse
import json
import os
import platform
import sys
import urllib.request
import urllib.error
from pathlib import Path

# ── MetaModule compatible plugin slugs ────────────────────────────────────────
# Source: https://metamodule.4ms.info/plugins
MM_SLUGS = [
    "21kHz",
    "4ms-ProducerPack",
    "4ms-ROMplers",
    "4ms-XOXDrums",
    "4msCompany",
    "Airwin2Rack",
    "AlliewayAudio_Freebies",
    "AmalgamatedHarmonics",
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

API = "https://api.vcvrack.com"


def get_platform_info():
    sys_name = platform.system()
    machine = platform.machine().lower()

    if sys_name == "Windows":
        os_key = "win"
    elif sys_name == "Darwin":
        os_key = "mac"
    else:
        os_key = "lin"

    if "arm" in machine or "aarch64" in machine:
        cpu_key = "arm64"
    else:
        cpu_key = "x64"

    return f"{os_key}-{cpu_key}"


def get_rack_paths(arch: str):
    sys_name = platform.system()
    if sys_name == "Windows":
        base = Path(os.environ.get("APPDATA", "")) / "Rack2"
    elif sys_name == "Darwin":
        base = Path.home() / "Documents" / "Rack2"
    else:
        base = Path.home() / ".local" / "share" / "Rack2"

    return {
        "settings": base / "settings.json",
        "plugins": base / f"plugins-{arch}",
    }


def read_token(settings_path: Path) -> str:
    if not settings_path.exists():
        return ""
    try:
        with open(settings_path) as f:
            return json.load(f).get("token", "")
    except Exception:
        return ""


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


def download_plugin(slug: str, version: str, arch: str, token: str, dest: Path) -> bool:
    url = f"{API}/download?slug={slug}&version={version}&arch={arch}"
    req = urllib.request.Request(url)
    if token:
        req.add_header("Cookie", f"token={token}")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        if len(data) < 1000:
            return False
        dest.write_bytes(data)
        return True
    except Exception:
        return False


def get_installed_version(plugin_dir: Path, slug: str) -> str:
    pjson = plugin_dir / slug / "plugin.json"
    if not pjson.exists():
        return ""
    try:
        with open(pjson) as f:
            return json.load(f).get("version", "")
    except Exception:
        return ""


def main():
    parser = argparse.ArgumentParser(description="Sync VCV Rack with MetaModule plugins")
    parser.add_argument("--check", action="store_true", help="Dry run — show what would change")
    parser.add_argument("--list", action="store_true", help="Print MetaModule plugin list and exit")
    parser.add_argument("--token", default="", help="Override VCV token")
    parser.add_argument("--arch", default="", help="Override platform arch (e.g. lin-x64)")
    args = parser.parse_args()

    if args.list:
        print("\n".join(sorted(MM_SLUGS)))
        return

    arch = args.arch or get_platform_info()
    paths = get_rack_paths(arch)
    token = args.token or read_token(paths["settings"])

    if not token:
        print("ERROR: No VCV token found.")
        print(f"  Open VCV Rack, log in via Library menu, then re-run this script.")
        print(f"  Expected settings file: {paths['settings']}")
        sys.exit(1)

    plugin_dir = paths["plugins"]
    plugin_dir.mkdir(parents=True, exist_ok=True)

    print(f"Platform : {arch}")
    print(f"Plugins  : {plugin_dir}")
    print(f"Mode     : {'DRY RUN' if args.check else 'SYNC'}")
    print()

    # Fetch manifests
    print("Fetching plugin versions from VCV Library...")
    try:
        manifests_data = api_get("/library/manifests?version=2", token)
    except RuntimeError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    manifests = manifests_data.get("manifests", {})

    downloaded = skipped = failed = 0

    for slug in MM_SLUGS:
        manifest = manifests.get(slug, {})
        version = manifest.get("version", "")
        arches = manifest.get("arches", {})

        if not version or not arches.get(arch):
            print(f"  SKIP {slug:40s} — not available for {arch}")
            skipped += 1
            continue

        installed = get_installed_version(plugin_dir, slug)

        if installed == version:
            print(f"  OK   {slug:40s} {version}")
            skipped += 1
            continue

        if installed:
            label = f"UPD  {slug:40s} {installed} → {version}"
        else:
            label = f"GET  {slug:40s} {version}"

        if args.check:
            print(f"  {label}  [dry run]")
            continue

        print(f"  {label}", end="", flush=True)
        out = plugin_dir / f"{slug}-{version}-{arch}.vcvplugin"
        ok = download_plugin(slug, version, arch, token, out)
        if ok:
            print("  ✓")
            downloaded += 1
        else:
            print("  ✗ FAILED")
            out.unlink(missing_ok=True)
            failed += 1

    print()
    print(f"Downloaded: {downloaded}  Skipped: {skipped}  Failed: {failed}")
    if downloaded:
        print("Restart VCV Rack to load new plugins.")


if __name__ == "__main__":
    main()
