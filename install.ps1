# Registers the connector as a hidden per-user task that starts at logon, and starts it now.
# Also puts the mav-wifi command on PATH and into your PowerShell profile.
#   -CommandOnly   only set up the mav-wifi command, leave the task alone
param([switch]$CommandOnly)

$TaskName = 'MAV WiFi Connector'
$script = Join-Path $PSScriptRoot 'mav-wifi-connector.ps1'
$binDir = Join-Path $PSScriptRoot 'bin'
$profileLine = "if (Test-Path '$PSScriptRoot\mav-wifi.profile.ps1') { . '$PSScriptRoot\mav-wifi.profile.ps1' }  # mav-wifi"

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$path = @($key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' | Where-Object { $_ })
if ($path -notcontains $binDir) {
    $key.SetValue('Path', (($path + $binDir) -join ';'), 'ExpandString')
    [Environment]::SetEnvironmentVariable('MAV_WIFI_PATH_REFRESH', '1', 'User')
    [Environment]::SetEnvironmentVariable('MAV_WIFI_PATH_REFRESH', $null, 'User')
    Write-Host "Added $binDir to your PATH."
}
$key.Close()

if (-not (Test-Path $PROFILE)) { New-Item $PROFILE -ItemType File -Force | Out-Null }
if (-not (Select-String -Path $PROFILE -SimpleMatch $profileLine -Quiet)) {
    Add-Content -Path $PROFILE -Value "`r`n$profileLine" -Encoding UTF8
    Write-Host "Added mav-wifi to $PROFILE."
}
Write-Host 'Open a new terminal to use the mav-wifi command.'
if ($CommandOnly) { return }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed and started '$TaskName'. Log: $(Join-Path $PSScriptRoot 'mav-wifi-connector.log')"
