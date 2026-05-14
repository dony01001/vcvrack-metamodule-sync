# sync.ps1 - VCV Rack <-> 4ms MetaModule plugin sync (Windows)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Subscribe
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Favorites
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 -IncludePaid
#
# Environment variable: set VCV_TOKEN=<token> to skip reading from settings.json

param(
    [switch]$Check,
    [switch]$List,
    [switch]$Subscribe,
    [switch]$Favorites,
    [switch]$IncludePaid,
    [string]$Token = "",
    [string]$Arch  = "win-x64"
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$API              = "https://api.vcvrack.com"
$MODULEFINDER_URL = "https://metamodule.4ms.info/modulefinder"
$USER_AGENT       = "vcvrack-metamodule-sync/1.0 (github.com/dony0/vcvrack-metamodule-sync)"
$BACKUP_KEEP      = 5
$RackRoot         = if (Test-Path "$env:LOCALAPPDATA\Rack2\settings.json") { "$env:LOCALAPPDATA\Rack2" } else { "$env:APPDATA\Rack2" }
$PluginDir        = "$RackRoot\plugins-$Arch"
$SettingsFile     = "$RackRoot\settings.json"

# MetaModule compatible slugs - source: https://metamodule.4ms.info/modulefinder
$MM_SLUGS = @(
    "21kHz","4ms-ProducerPack","4ms-ROMplers","4ms-XOXDrums","4msCompany",
    "Airwin2Rack","AlliewayAudio_Freebies","AmalgamatedHarmonics","AudibleInstruments",
    "Autinn","Bastl","Befaco","Bidoo","BlackNoiseModular","Bogaudio","CVfunk","Cella",
    "ChowDSP","CosineKitty-Sapphire","CountModula","CuteLab","DrumKit",
    "ESeries","FehlerFabrik-Suite","Fundamental","Geodesics","HetrickCV",
    "ImpromptuModular","InfrasonicAudio","JW-Modules","KRTPluginA","MADZINE","MSM","MUS-X",
    "MockbaModular","Moffenzeef","NANOModules","NOI","NonlinearCircuits",
    "Nozoid","Ondas","OrangeLine","PathSet","RPJ","RebelTech","Rigatoni",
    "SanguineMonsters","SanguineMutants","SeasideModular","SickoCV",
    "SignalFunctionSet","SonusModular","StellareModular","StellareModular-CreativeSuite",
    "StudioSixPlusOne","UnfilteredVolume1","UnfilteredVolume2","Valley","Venom","WordGenerator",
    "dBiz","eightfold","kocmoc","mscHack","nullpath","squinkylabs-plug1",
    "vanTies","voxglitch"
)

# Paid plugins -- require purchase on library.vcvrack.com before download
$MM_PAID = @{
    "StellareModular-CreativeSuite" = '$25'
    "UnfilteredVolume1"             = '$25'
    "UnfilteredVolume2"             = '$30'
}

# H4: allowlist set for O(1) lookup
$MM_SLUGS_SET = [System.Collections.Generic.HashSet[string]]::new([string[]]$MM_SLUGS)

$ActiveSlugs = if ($IncludePaid) { $MM_SLUGS } else { $MM_SLUGS | Where-Object { -not $MM_PAID.ContainsKey($_) } }

if ($List) {
    $ActiveSlugs | Sort-Object | ForEach-Object {
        $price = if ($MM_PAID.ContainsKey($_)) { "  [$($MM_PAID[$_])]" } else { "" }
        "$_$price"
    }
    exit 0
}

# -- Helpers ------------------------------------------------------------------

function Test-RackRunning {
    # H3: detect if VCV Rack is open
    $proc = Get-Process -Name "Rack" -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

function Test-Interactive {
    # M4: true when running in a real console (not Task Scheduler / piped)
    return [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)
}

function Invoke-ApiGet {
    # Centralised web request with User-Agent; $UseToken = $true attaches cookie
    param([string]$Uri, [hashtable]$Headers = @{})
    $Headers["User-Agent"] = $USER_AGENT
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -UseBasicParsing
}

function Invoke-ApiDownload {
    param([string]$Uri, [hashtable]$Headers = @{}, [string]$OutFile)
    $Headers["User-Agent"] = $USER_AGENT
    Invoke-WebRequest -Uri $Uri -Headers $Headers -OutFile $OutFile -UseBasicParsing | Out-Null
}

function Test-ZipFile {
    # C1: check magic bytes (PK\x03\x04) then validate zip structure
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 4) { return $false }
        if ($bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B -or $bytes[2] -ne 0x03 -or $bytes[3] -ne 0x04) {
            return $false
        }
        # Try opening as zip archive
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $zip.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Invoke-AtomicWrite {
    # C2: write JSON to .tmp then rename to target (atomic on same volume)
    param([string]$Path, [string]$Json)
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

function Backup-AndRotate {
    # H2: create timestamped backup, delete oldest beyond $BACKUP_KEEP
    param([string]$Path, [string]$Prefix)
    $dir  = Split-Path $Path -Parent
    $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
    $dest = Join-Path $dir "$Prefix.$ts.bak"
    Copy-Item $Path $dest
    $old = Get-ChildItem $dir -Filter "$Prefix.*.bak" | Sort-Object Name
    if ($old.Count -gt $BACKUP_KEEP) {
        $old | Select-Object -First ($old.Count - $BACKUP_KEEP) | Remove-Item -Force
    }
    return $dest
}

# -- Token --------------------------------------------------------------------
# H1: prefer VCV_TOKEN env var over settings.json
if (-not $Token) { $Token = $env:VCV_TOKEN }
if (-not $Token) {
    if (Test-Path $SettingsFile) {
        try { $Token = (Get-Content $SettingsFile -Raw | ConvertFrom-Json).token } catch {}
    }
}
if (-not $Token) {
    Write-Error "No VCV token found. Set VCV_TOKEN env var, or open VCV Rack, log in via Library menu, then re-run."
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

# -- Fetch manifests ----------------------------------------------------------
Write-Host "Fetching plugin versions from VCV Library..."
# L3: manifests endpoint is public -- no auth token needed
try {
    $manifestsData = Invoke-ApiGet -Uri "$API/library/manifests?version=2"
} catch {
    Write-Error "Failed to fetch manifests: check internet connection."
    exit 1
}
$manifests   = $manifestsData.manifests
$downloaded  = 0
$skipped     = 0
$failed      = 0
$toSubscribe = [System.Collections.Generic.List[string]]::new()

$authHeaders = @{ Cookie = "token=$Token" }

foreach ($slug in $ActiveSlugs) {
    $manifest = $manifests.$slug
    if (-not $manifest) {
        Write-Host ("  SKIP {0,-44} not in VCV Library" -f $slug)
        $skipped++
        continue
    }

    $version = $manifest.version
    $archOk  = $manifest.arches.$Arch
    if (-not $version -or -not $archOk) {
        Write-Host ("  SKIP {0,-44} not available for $Arch" -f $slug)
        $skipped++
        continue
    }

    $installedVer = ""
    $pjson = "$PluginDir\$slug\plugin.json"
    if (Test-Path $pjson) {
        try { $installedVer = (Get-Content $pjson -Raw | ConvertFrom-Json).version } catch {}
    }

    if ($installedVer -eq $version) {
        Write-Host ("  OK   {0,-44} {1}" -f $slug, $version)
        $skipped++
        continue
    }

    $label = if ($installedVer) {
        "UPD  {0,-44} $installedVer -> $version" -f $slug
    } else {
        "GET  {0,-44} $version" -f $slug
    }

    if ($Check) { Write-Host "  $label  [dry run]"; continue }

    Write-Host -NoNewline "  $label"

    $outFile = "$PluginDir\$slug-$version-$Arch.vcvplugin"
    $tmpFile = "$outFile.tmp"
    try {
        Invoke-ApiDownload -Uri "$API/download?slug=$slug&version=$version&arch=$Arch" `
            -Headers $authHeaders -OutFile $tmpFile

        # C1: validate zip before committing
        if ((Test-Path $tmpFile) -and (Test-ZipFile $tmpFile)) {
            # C2: atomic rename
            Move-Item -Path $tmpFile -Destination $outFile -Force
            Write-Host "  OK"
            $downloaded++
        } else {
            if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            Write-Host "  FAILED (corrupt or empty response)"
            $failed++
        }
    } catch {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
        # M6: sanitize error -- don't echo raw $_ which may contain token
        $errMsg = $_.Exception.Message -replace "token=[^&\s;]+", "token=***"
        if ($errMsg -match "not owned|not subscribed|downloadable|403|401") {
            Write-Host "  NEEDS SUBSCRIBE"
            $toSubscribe.Add($slug)
        } else {
            Write-Host "  FAILED (network error)"
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
    foreach ($slug in $toSubscribe) { Write-Host "  https://library.vcvrack.com/$slug" }

    if ($Subscribe) {
        if (Test-Interactive) {
            Write-Host ""
            $ans = Read-Host "Open $($toSubscribe.Count) browser tab(s)? [y/N]"
            if ($ans -eq "y" -or $ans -eq "Y") {
                foreach ($slug in $toSubscribe) {
                    Start-Process "https://library.vcvrack.com/$slug"
                    Start-Sleep -Milliseconds 300
                }
                Write-Host "Click Subscribe on each tab, then re-run sync."
            }
        } else {
            # M4: non-interactive (Task Scheduler, piped) -- skip prompt, just print
            Write-Host ""
            Write-Host "(-Subscribe skipped: not running in interactive console)"
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
    Write-Host "Marking MetaModule modules as favorites in settings.json..."

    # H3: abort if Rack is running (changes would be overwritten on exit)
    if (Test-RackRunning) {
        Write-Error "VCV Rack is currently running. Close it first, then re-run with -Favorites."
        exit 1
    }

    Write-Host "  NOTE: Keep VCV Rack closed until this finishes."

    if (-not (Test-Path $SettingsFile)) {
        Write-Error "settings.json not found. Open VCV Rack once, log in, close it, then re-run."
        exit 1
    }

    # H2: backup with rotation
    $backupPath = Backup-AndRotate -Path $SettingsFile -Prefix "settings.backup"
    Write-Host "  Backup: $(Split-Path $backupPath -Leaf)"

    # Load settings
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

    # Ensure moduleInfos exists
    if (-not $settings.PSObject.Properties["moduleInfos"]) {
        $settings | Add-Member -NotePropertyName "moduleInfos" -NotePropertyValue ([PSCustomObject]@{})
    }

    # Fetch exact MM module list from modulefinder
    Write-Host "  Fetching module list from metamodule.4ms.info/modulefinder..."
    $mmModules = @{}
    try {
        $html = (Invoke-WebRequest -Uri $MODULEFINDER_URL -UseBasicParsing -TimeoutSec 30 `
            -Headers @{"User-Agent" = $USER_AGENT}).Content
        [regex]::Matches($html, 'https://library\.vcvrack\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)') | ForEach-Object {
            $p = $_.Groups[1].Value; $mod = $_.Groups[2].Value
            # H4: only accept slugs in our known allowlist
            if (-not $MM_SLUGS_SET.Contains($p)) { return }
            if (-not $mmModules[$p]) { $mmModules[$p] = [System.Collections.Generic.List[string]]::new() }
            if (-not $mmModules[$p].Contains($mod)) { $mmModules[$p].Add($mod) }
        }
        $totalMods = ($mmModules.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        Write-Host "  Found $totalMods MM-compatible modules across $($mmModules.Count) plugins"
    } catch {
        Write-Host "  WARNING: modulefinder unreachable -- falling back to local plugin.json"
    }

    $addedMods  = 0
    $skippedFav = 0

    foreach ($slug in $MM_SLUGS) {
        if ($mmModules.Count -gt 0) {
            if (-not $mmModules.ContainsKey($slug)) {
                Write-Host ("  SKIP {0,-44} not in modulefinder" -f $slug)
                $skippedFav++; continue
            }
            $moduleSlugs = @($mmModules[$slug])
        } else {
            $pjson = "$PluginDir\$slug\plugin.json"
            if (-not (Test-Path $pjson)) {
                Write-Host ("  SKIP {0,-44} not installed" -f $slug)
                $skippedFav++; continue
            }
            try { $moduleSlugs = @((Get-Content $pjson -Raw | ConvertFrom-Json).modules | ForEach-Object { $_.slug }) }
            catch { Write-Host ("  SKIP {0,-44} could not read plugin.json" -f $slug); $skippedFav++; continue }
        }
        if ($moduleSlugs.Count -eq 0) { $skippedFav++; continue }

        # Ensure plugin entry exists in moduleInfos
        if (-not $settings.moduleInfos.PSObject.Properties[$slug]) {
            $settings.moduleInfos | Add-Member -NotePropertyName $slug -NotePropertyValue ([PSCustomObject]@{})
        }
        $pluginInfo = $settings.moduleInfos.$slug
        $newCount = 0

        foreach ($mod in $moduleSlugs) {
            if (-not $pluginInfo.PSObject.Properties[$mod]) {
                $pluginInfo | Add-Member -NotePropertyName $mod -NotePropertyValue ([PSCustomObject]@{ favorite = $true })
                $newCount++
            } elseif ($pluginInfo.$mod.favorite -ne $true) {
                $pluginInfo.$mod | Add-Member -NotePropertyName "favorite" -NotePropertyValue $true -Force
                $newCount++
            }
        }
        $addedMods += $newCount
        $source = if ($mmModules.Count -gt 0) { "modulefinder" } else { "local" }
        Write-Host ("  FAV  {0,-44} {1} modules (+{2} new)  [{3}]" -f $slug, $moduleSlugs.Count, $newCount, $source)
    }

    # C2 + M2: atomic write with full depth
    $json = $settings | ConvertTo-Json -Depth 100
    Invoke-AtomicWrite -Path $SettingsFile -Json $json

    Write-Host ""
    Write-Host "+$addedMods modules marked as favorite. $skippedFav plugins skipped."
    Write-Host "Open VCV Rack and filter by Favorites to see MetaModule-compatible modules."
}
