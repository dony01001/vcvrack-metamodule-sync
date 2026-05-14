# install-windows.ps1 - one-time setup on Windows
# Registers a weekly Task Scheduler job to run sync.ps1
#
# Must run as Administrator (Task Scheduler registration requires elevation).
# Right-click PowerShell -> "Run as administrator", then:
#   Set-Location "<path to repo>"
#   .\install-windows.ps1

# H5: require Administrator
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must run as Administrator. Right-click PowerShell and choose 'Run as administrator'."
    exit 1
}

# L1: $PSScriptRoot is reliable; $MyInvocation.MyCommand.Path can fail in some hosts
$SyncScript = Join-Path $PSScriptRoot "sync.ps1"

if (-not (Test-Path $SyncScript)) {
    Write-Error "sync.ps1 not found in $PSScriptRoot"
    exit 1
}

$taskName   = "VCVRack-MetaModule-Sync"
$action     = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$SyncScript`" -Favorites"
$trigger    = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "9:00AM"
$settings   = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action   $action `
    -Trigger  $trigger `
    -Settings $settings `
    -Description "Sync VCV Rack plugins with 4ms MetaModule compatible list" `
    -Force | Out-Null

Write-Host "Scheduled task '$taskName' registered (runs every Monday 9am)"
Write-Host ""
Write-Host "Run a manual sync anytime with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$SyncScript`""
