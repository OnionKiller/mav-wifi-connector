$TaskName = 'MAV WiFi Connector'
$binDir = Join-Path $PSScriptRoot 'bin'

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "Removed '$TaskName'."

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$path = @($key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' | Where-Object { $_ })
if ($path -contains $binDir) {
    $key.SetValue('Path', (($path | Where-Object { $_ -ne $binDir }) -join ';'), 'ExpandString')
    Write-Host "Removed $binDir from your PATH."
}
$key.Close()

if (Test-Path $PROFILE) {
    $lines = @(Get-Content $PROFILE -Encoding UTF8)
    $kept = @($lines | Where-Object { $_ -notlike '*mav-wifi.profile.ps1*# mav-wifi' })
    if ($kept.Count -ne $lines.Count) {
        Set-Content -Path $PROFILE -Value $kept -Encoding UTF8
        Write-Host "Removed mav-wifi from $PROFILE."
    }
}
