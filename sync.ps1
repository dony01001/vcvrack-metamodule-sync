# sync.ps1 - VCV Rack <-> 4ms MetaModule plugin sync (Windows)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Subscribe
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Favorites
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -IncludePaid

param(
    [switch]$Check,
    [switch]$List,
    [switch]$Subscribe,
    [switch]$Favorites,
    [switch]$IncludePaid,
    [string]$Token = "",
    [string]$Arch  = "win-x64"
)

$API           = "https://api.vcvrack.com"
$RackRoot      = if (Test-Path "$env:LOCALAPPDATA\Rack2\settings.json") { "$env:LOCALAPPDATA\Rack2" } else { "$env:APPDATA\Rack2" }
$PluginDir     = "$RackRoot\plugins-$Arch"
$SettingsFile  = "$RackRoot\settings.json"
$FavoritesFile = "$RackRoot\favoriteModules.json"

# MetaModule compatible slugs - source: https://metamodule.4ms.info/plugins
$MM_SLUGS = @(
    "21kHz","4ms-ProducerPack","4ms-ROMplers","4ms-XOXDrums","4msCompany",
    "Airwin2Rack","AlliewayAudio_Freebies","AmalgamatedHarmonics","Autinn",
    "Bastl","Befaco","Bidoo","BlackNoiseModular","Bogaudio","CVfunk","Cella",
    "ChowDSP","CosineKitty-Sapphire","CountModula","CuteLab","DrumKit",
    "ESeries","FehlerFabrik-Suite","Fundamental","Geodesics","HetrickCV",
    "ImpromptuModular","JW-Modules","KRTPluginA","MADZINE","MSM","MUS-X",
    "MockbaModular","Moffenzeef","NANOModules","NOI","NonlinearCircuits",
    "Nozoid","OrangeLine","PathSet","RPJ","RebelTech","Rigatoni",
    "SanguineMonsters","SanguineMutants","SeasideModular","SickoCV",
    "SignalFunctionSet","SonusModular","StellareModular","StudioSixPlusOne",
    "UnfilteredVolume1","UnfilteredVolume2","Valley","Venom","WordGenerator",
    "dBiz","eightfold","kocmoc","mscHack","nullpath","squinkylabs-plug1",
    "vanTies","voxglitch"
)

# Paid plugins -- require purchase on library.vcvrack.com before download
$MM_PAID = @{
    "UnfilteredVolume1" = '$25'
    "UnfilteredVolume2" = '$30'
}

$ActiveSlugs = if ($IncludePaid) { $MM_SLUGS } else { $MM_SLUGS | Where-Object { -not $MM_PAID.ContainsKey($_) } }

if ($List) {
    $ActiveSlugs | Sort-Object | ForEach-Object {
        $price = if ($MM_PAID.ContainsKey($_)) { "  [$($MM_PAID[$_])]" } else { "" }
        "$_$price"
    }
    exit 0
}

# Read token
if (-not $Token) {
    if (Test-Path $SettingsFile) {
        $Token = (Get-Content $SettingsFile -Raw | ConvertFrom-Json).token
    }
}

if (-not $Token) {
    Write-Error "No VCV token found. Open VCV Rack, log in via Library menu, then re-run."
    exit 1
}

New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null

$paidNote = if ($IncludePaid) { " (including paid)" } else { " (+ $($MM_PAID.Count) paid skipped, use -IncludePaid)" }
$mode     = if ($Check) { "DRY RUN" } else { "SYNC" }
Write-Host "Platform : $Arch"
Write-Host "Plugins  : $PluginDir"
Write-Host "Mode     : $mode"
Write-Host "Syncing  : $($ActiveSlugs.Count) plugins$paidNote"
Write-Host ""

Write-Host "Fetching plugin versions from VCV Library..."
$headers = @{ Cookie = "token=$Token" }
try {
    $manifestsData = Invoke-RestMethod -Uri "$API/library/manifests?version=2" -Headers $headers
} catch {
    Write-Error "Failed to fetch manifests: $_"
    exit 1
}
$manifests   = $manifestsData.manifests
$downloaded  = 0
$skipped     = 0
$failed      = 0
$toSubscribe = [System.Collections.Generic.List[string]]::new()

foreach ($slug in $ActiveSlugs) {
    $manifest = $manifests.$slug
    if (-not $manifest) {
        Write-Host ("  SKIP {0,-40} not in VCV Library" -f $slug)
        $skipped++
        continue
    }

    $version = $manifest.version
    $archOk  = $manifest.arches.$Arch

    if (-not $version -or -not $archOk) {
        Write-Host ("  SKIP {0,-40} not available for $Arch" -f $slug)
        $skipped++
        continue
    }

    $installedVer = ""
    $pjson = "$PluginDir\$slug\plugin.json"
    if (Test-Path $pjson) {
        try { $installedVer = (Get-Content $pjson -Raw | ConvertFrom-Json).version } catch {}
    }

    if ($installedVer -eq $version) {
        Write-Host ("  OK   {0,-40} {1}" -f $slug, $version)
        $skipped++
        continue
    }

    $label = if ($installedVer) {
        "UPD  {0,-40} $installedVer -> $version" -f $slug
    } else {
        "GET  {0,-40} $version" -f $slug
    }

    if ($Check) {
        Write-Host "  $label  [dry run]"
        continue
    }

    Write-Host -NoNewline "  $label"

    $outFile = "$PluginDir\$slug-$version-$Arch.vcvplugin"
    try {
        Invoke-WebRequest -Uri "$API/download?slug=$slug&version=$version&arch=$Arch" `
            -Headers $headers -OutFile $outFile -UseBasicParsing | Out-Null
        if ((Get-Item $outFile -ErrorAction SilentlyContinue).Length -gt 1000) {
            Write-Host "  OK"
            $downloaded++
        } else {
            if (Test-Path $outFile) { Remove-Item $outFile -Force }
            Write-Host "  FAILED (empty response)"
            $failed++
        }
    } catch {
        if (Test-Path $outFile) { Remove-Item $outFile -Force }
        $errBody = $_.ErrorDetails.Message
        if ($errBody -match "not owned|not subscribed|downloadable") {
            Write-Host "  NEEDS SUBSCRIBE"
            $toSubscribe.Add($slug)
        } else {
            Write-Host "  FAILED ($_)"
            $failed++
        }
    }
}

Write-Host ""
Write-Host "Downloaded: $downloaded  Skipped: $skipped  Failed: $failed  Need subscribe: $($toSubscribe.Count)"

# -- Subscribe list -----------------------------------------------------------
if ($toSubscribe.Count -gt 0) {
    Write-Host ""
    Write-Host "Subscribe these plugins for free at library.vcvrack.com:"
    foreach ($slug in $toSubscribe) {
        Write-Host "  https://library.vcvrack.com/$slug"
    }

    if ($Subscribe) {
        Write-Host ""
        $ans = Read-Host "Open $($toSubscribe.Count) browser tabs? [y/N]"
        if ($ans -eq "y" -or $ans -eq "Y") {
            foreach ($slug in $toSubscribe) {
                Start-Process "https://library.vcvrack.com/$slug"
                Start-Sleep -Milliseconds 300
            }
            Write-Host "Click Subscribe on each tab, then re-run sync."
        }
    } else {
        Write-Host ""
        Write-Host "Tip: run with -Subscribe to open all URLs in browser automatically."
    }
}

if ($downloaded -gt 0) {
    Write-Host ""
    Write-Host "Restart VCV Rack to load new plugins."
}

# -- Favorites ----------------------------------------------------------------
if ($Favorites) {
    Write-Host ""
    Write-Host "Updating VCV Rack favorites with MetaModule modules..."

    $fav = @{}
    if (Test-Path $FavoritesFile) {
        # Backup before modifying
        $ts     = Get-Date -Format "yyyyMMdd_HHmmss"
        $backup = [System.IO.Path]::ChangeExtension($FavoritesFile, $null).TrimEnd('.') + ".backup.$ts.json"
        Copy-Item $FavoritesFile $backup
        Write-Host "  Backup saved: $(Split-Path $backup -Leaf)"
        try {
            $raw = Get-Content $FavoritesFile -Raw | ConvertFrom-Json
            $raw.PSObject.Properties | ForEach-Object { $fav[$_.Name] = [System.Collections.Generic.List[string]]$_.Value }
        } catch { $fav = @{} }
    }

    $addedMods = 0
    $skippedFav = 0

    foreach ($slug in $MM_SLUGS) {   # always use full list for favorites
        $pjson = "$PluginDir\$slug\plugin.json"
        if (-not (Test-Path $pjson)) {
            Write-Host ("  SKIP {0,-40} not installed" -f $slug)
            $skippedFav++
            continue
        }
        try {
            $pluginMeta  = Get-Content $pjson -Raw | ConvertFrom-Json
            $moduleSlugs = @($pluginMeta.modules | ForEach-Object { $_.slug })
        } catch {
            Write-Host ("  SKIP {0,-40} could not read plugin.json" -f $slug)
            $skippedFav++
            continue
        }

        if ($moduleSlugs.Count -eq 0) { $skippedFav++; continue }

        $existing = if ($fav.ContainsKey($slug)) { @($fav[$slug]) } else { @() }
        $newMods  = $moduleSlugs | Where-Object { $existing -notcontains $_ }
        $fav[$slug] = @($existing) + @($newMods)
        $addedMods += $newMods.Count

        Write-Host ("  FAV  {0,-40} {1} modules (+{2} new)" -f $slug, $moduleSlugs.Count, $newMods.Count)
    }

    $fav | ConvertTo-Json -Depth 5 | Set-Content $FavoritesFile -Encoding UTF8

    Write-Host ""
    Write-Host "+$addedMods modules added to favorites. $skippedFav plugins skipped (not installed)."
    Write-Host "Restart VCV Rack and filter by Favorites to see MetaModule-compatible modules."
}
