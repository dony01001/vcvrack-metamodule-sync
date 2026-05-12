# sync.ps1 — VCV Rack ↔ 4ms MetaModule plugin sync (Windows)
# Run in PowerShell: .\sync.ps1
# Or dry-run:        .\sync.ps1 -Check

param(
    [switch]$Check,
    [switch]$List,
    [string]$Token = "",
    [string]$Arch  = "win-x64"
)

$API        = "https://api.vcvrack.com"
$PluginDir  = "$env:APPDATA\Rack2\plugins-$Arch"
$SettingsFile = "$env:APPDATA\Rack2\settings.json"

# MetaModule compatible slugs — source: https://metamodule.4ms.info/plugins
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

if ($List) { $MM_SLUGS | Sort-Object; exit 0 }

# Read token from settings if not passed
if (-not $Token) {
    if (Test-Path $SettingsFile) {
        $settings = Get-Content $SettingsFile | ConvertFrom-Json
        $Token = $settings.token
    }
}

if (-not $Token) {
    Write-Error "No VCV token found. Open VCV Rack, log in via Library menu, then re-run."
    exit 1
}

New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null

$mode = if ($Check) { "DRY RUN" } else { "SYNC" }
Write-Host "Platform : $Arch"
Write-Host "Plugins  : $PluginDir"
Write-Host "Mode     : $mode"
Write-Host ""

# Fetch manifests
Write-Host "Fetching plugin versions from VCV Library..."
$headers = @{ Cookie = "token=$Token" }
try {
    $manifestsData = Invoke-RestMethod -Uri "$API/library/manifests?version=2" -Headers $headers
} catch {
    Write-Error "Failed to fetch manifests: $_"
    exit 1
}
$manifests = $manifestsData.manifests

$downloaded = $skipped = $failed = 0

foreach ($slug in $MM_SLUGS) {
    $manifest = $manifests.$slug
    if (-not $manifest) {
        Write-Host ("  SKIP {0,-40} — not in VCV Library" -f $slug)
        $skipped++
        continue
    }

    $version = $manifest.version
    $archOk  = $manifest.arches.$Arch

    if (-not $version -or -not $archOk) {
        Write-Host ("  SKIP {0,-40} — not available for $Arch" -f $slug)
        $skipped++
        continue
    }

    # Check installed version
    $installedVer = ""
    $pjson = "$PluginDir\$slug\plugin.json"
    if (Test-Path $pjson) {
        try {
            $installedVer = (Get-Content $pjson | ConvertFrom-Json).version
        } catch {}
    }

    if ($installedVer -eq $version) {
        Write-Host ("  OK   {0,-40} {1}" -f $slug, $version)
        $skipped++
        continue
    }

    if ($installedVer) {
        $label = "UPD  {0,-40} $installedVer → $version" -f $slug
    } else {
        $label = "GET  {0,-40} $version" -f $slug
    }

    if ($Check) {
        Write-Host "  $label  [dry run]"
        continue
    }

    Write-Host -NoNewline "  $label"

    $outFile = "$PluginDir\$slug-$version-$Arch.vcvplugin"
    try {
        Invoke-WebRequest -Uri "$API/download?slug=$slug&version=$version&arch=$Arch" `
            -Headers $headers -OutFile $outFile -UseBasicParsing
        if ((Get-Item $outFile).Length -gt 1000) {
            Write-Host "  OK"
            $downloaded++
        } else {
            Remove-Item $outFile -Force
            Write-Host "  FAILED (empty)"
            $failed++
        }
    } catch {
        if (Test-Path $outFile) { Remove-Item $outFile -Force }
        Write-Host "  FAILED ($_)"
        $failed++
    }
}

Write-Host ""
Write-Host "Downloaded: $downloaded  Skipped: $skipped  Failed: $failed"
if ($downloaded -gt 0) {
    Write-Host "Restart VCV Rack to load new plugins."
}
