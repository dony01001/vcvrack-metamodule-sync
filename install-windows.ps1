# install-windows.ps1 — one-time setup on Windows
# Registers a weekly Task Scheduler job to run sync.ps1

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SyncScript = "$ScriptDir\sync.ps1"

if (-not (Test-Path $SyncScript)) {
    Write-Error "sync.ps1 not found in $ScriptDir"
    exit 1
}

$taskName   = "VCVRack-MetaModule-Sync"
$action     = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$SyncScript`""
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
