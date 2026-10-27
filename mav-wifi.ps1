<#
.SYNOPSIS
Controls the MAV WiFi Connector.

.DESCRIPTION
The MAV WiFi Connector runs in the background and accepts the MAV on-board Wi-Fi captive portal
for you whenever you are on a MAVSTART network. mav-wifi starts and stops it, shows its state
and log, and changes its settings.

Commands:
  start                   Start the connector now.
                          -NoConsole  Start it directly in a headless console, with no window at all.
  stop                    Stop the connector now. It starts again at the next logon unless autostart is off.
  status                  Show whether the connector is running, and its main settings. Default command.
  log                     Show the last lines of mav-wifi-connector.log.
                          -Lines <n>  How many lines to show (default 20).
                          -Follow     Keep printing new lines until Ctrl+C.
  autostart [on|off]      Show, or turn on or off, starting the connector at logon.
  config                  Show all settings and where the config file is.
  config <name> <value>   Change a setting. A running connector picks it up at its next check.

Settings (stored in mav-wifi.config.json next to this script):
  IntervalSeconds   Seconds between internet checks (default 5). A check also runs right away
                    whenever Windows reports a network change.
  NetworkPattern    Regex for the Wi-Fi names to act on (default ^MAVSTART). On other networks
                    the connector does nothing.
  Autostart         true or false: start the connector at logon (default true).

Press Tab after "mav-wifi " to complete commands, or Ctrl+Space to see them with descriptions.

.PARAMETER Command
start, stop, status, log, autostart or config. Defaults to status.

.PARAMETER Setting
With autostart: on or off. With config: the setting name.

.PARAMETER Value
With config: the new value for the setting.

.PARAMETER NoConsole
With start: run the connector directly in a headless console instead of through the scheduled task.

.PARAMETER Lines
With log: how many lines to show. Defaults to 20.

.PARAMETER Follow
With log: keep printing new lines until Ctrl+C.

.EXAMPLE
mav-wifi start

Starts the connector now through the "MAV WiFi Connector" scheduled task.

.EXAMPLE
mav-wifi start -NoConsole

Starts the connector directly in a headless console, with no window at all.
Works without the scheduled task.

.EXAMPLE
mav-wifi stop

Stops the connector now. It starts again at the next logon unless autostart is off.

.EXAMPLE
mav-wifi status

Shows whether the connector is running, whether it starts at logon, and its check interval.

.EXAMPLE
mav-wifi log -Lines 50

Shows the last 50 lines of the log. Without -Lines, it shows the last 20.

.EXAMPLE
mav-wifi log -Follow

Keeps printing new log lines as they are written. Press Ctrl+C to quit.

.EXAMPLE
mav-wifi autostart off

Keeps the connector from starting at logon. "mav-wifi start" still starts it by hand.
"mav-wifi autostart on" turns logon startup back on.

.EXAMPLE
mav-wifi config IntervalSeconds 30

Checks the internet every 30 seconds instead of every 5. A running connector picks it up
at its next check.

.EXAMPLE
mav-wifi config

Shows all settings and the path of the config file.

.NOTES
Files next to the script:
  mav-wifi-connector.ps1      the connector itself
  mav-wifi.config.json        settings (see "Settings" above); you can also edit it by hand
  mav-wifi-connector.log      its log (rotated to .log.old after 1 MB)
  install.ps1 / uninstall.ps1 set up or remove the logon task, PATH entry and profile line
  README.md                   full documentation
#>
param(
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete)
        ([ordered]@{
            start     = 'Start the connector now (add -NoConsole to run it without a console window)'
            stop      = 'Stop the connector now'
            status    = 'Show whether the connector is running, and its main settings'
            log       = 'Show the log (-Lines <n> for more lines, -Follow to keep watching)'
            autostart = 'Show, or turn on or off, starting the connector at logon'
            config    = 'Show or change settings (IntervalSeconds, NetworkPattern, Autostart)'
        }).GetEnumerator() | Where-Object Key -like "$wordToComplete*" | ForEach-Object {
            [Management.Automation.CompletionResult]::new($_.Key, $_.Key, 'ParameterValue', $_.Value)
        }
    })]
    [string]$Command = 'status',
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $items = switch ($fakeBoundParameters['Command']) {
            'autostart' { [ordered]@{ on = 'Start the connector at logon'; off = 'Do not start the connector at logon' } }
            'config' {
                [ordered]@{
                    IntervalSeconds = 'Seconds between internet checks (default 5)'
                    NetworkPattern  = 'Regex for the Wi-Fi names to act on (default ^MAVSTART)'
                    Autostart       = 'true or false: start the connector at logon (default true)'
                }
            }
        }
        if ($items) {
            $items.GetEnumerator() | Where-Object Key -like "$wordToComplete*" | ForEach-Object {
                [Management.Automation.CompletionResult]::new($_.Key, $_.Key, 'ParameterValue', $_.Value)
            }
        }
    })]
    [string]$Setting,
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        if ($fakeBoundParameters['Command'] -eq 'config' -and $fakeBoundParameters['Setting'] -eq 'Autostart') {
            'true', 'false' | Where-Object { $_ -like "$wordToComplete*" }
        }
    })]
    [string]$Value,
    [switch]$NoConsole,
    [int]$Lines = 20,
    [switch]$Follow
)

$TaskName   = 'MAV WiFi Connector'
$Script     = Join-Path $PSScriptRoot 'mav-wifi-connector.ps1'
$LogFile    = Join-Path $PSScriptRoot 'mav-wifi-connector.log'
$ConfigFile = Join-Path $PSScriptRoot 'mav-wifi.config.json'
$Defaults   = [ordered]@{ IntervalSeconds = 5; NetworkPattern = '^MAVSTART'; Autostart = $true }

function Get-ConnectorProcess {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
        Where-Object { $_.CommandLine -like '*mav-wifi-connector.ps1*' }
}

function Get-Task {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

function Get-Config {
    $config = [ordered]@{}
    foreach ($key in $Defaults.Keys) { $config[$key] = $Defaults[$key] }
    if (Test-Path $ConfigFile) {
        (Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties |
            Where-Object { $config.Contains($_.Name) } | ForEach-Object { $config[$_.Name] = $_.Value }
    }
    $config
}

function Save-Config($Config) {
    $lines = foreach ($key in $Config.Keys) { '  "{0}": {1}' -f $key, (ConvertTo-Json $Config[$key]) }
    Set-Content -Path $ConfigFile -Value "{`r`n$($lines -join ",`r`n")`r`n}" -Encoding UTF8
}

function ConvertTo-SettingValue([string]$Name, [string]$Text) {
    switch ($Name) {
        'IntervalSeconds' {
            $seconds = 0
            if ([int]::TryParse($Text, [ref]$seconds) -and $seconds -ge 1) { return $seconds }
            Write-Host 'IntervalSeconds must be a whole number of seconds, 1 or more.'
        }
        'NetworkPattern' {
            try { [void][regex]::new($Text); return $Text }
            catch { Write-Host "NetworkPattern is not a valid regex: $($_.Exception.InnerException.Message)" }
        }
        'Autostart' {
            if ($Text -in 'on', 'true', 'yes', '1') { return $true }
            if ($Text -in 'off', 'false', 'no', '0') { return $false }
            Write-Host 'Autostart must be on or off.'
        }
    }
}

switch ($Command) {
    'start' {
        $config = Get-Config
        if (Get-ConnectorProcess) {
            Write-Host 'Already running.'
        } elseif ($NoConsole -or -not $config.Autostart -or -not (Get-Task)) {
            Start-Process conhost.exe -ArgumentList '--headless', 'powershell.exe', '-NoProfile',
                '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '-Manual'
            Write-Host 'Started with no console window.'
        } else {
            Start-ScheduledTask -TaskName $TaskName
            Write-Host "Started '$TaskName'."
        }
    }
    'stop' {
        if (Get-Task) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
        Get-ConnectorProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  Stopped' -f (Get-Date)) -Encoding UTF8
        if ((Get-Config).Autostart -and (Get-Task)) {
            Write-Host 'Stopped. It starts again at the next logon; to prevent that: mav-wifi autostart off'
        } else {
            Write-Host 'Stopped.'
        }
    }
    'status' {
        $config = Get-Config
        $running = if (Get-ConnectorProcess) { 'yes' } else { 'no' }
        $atLogon = if (-not (Get-Task)) { 'no (task not installed)' }
                   elseif (-not $config.Autostart) { 'no (autostart off)' }
                   else { 'yes' }
        Write-Host "Running:          $running"
        Write-Host "Starts at logon:  $atLogon"
        Write-Host "Check interval:   $($config.IntervalSeconds) s"
        Write-Host "Network pattern:  $($config.NetworkPattern)"
    }
    'log' {
        if (-not (Test-Path $LogFile)) {
            Write-Host 'No log yet.'
            return
        }
        Get-Content $LogFile -Tail $Lines -Wait:$Follow
    }
    'autostart' {
        $config = Get-Config
        if (-not $Setting) {
            Write-Host "Autostart: $(if ($config.Autostart) { 'on' } else { 'off' })"
            return
        }
        $enabled = ConvertTo-SettingValue 'Autostart' $Setting
        if ($null -eq $enabled) { return }
        $config.Autostart = $enabled
        Save-Config $config
        if ($enabled) {
            Write-Host 'Autostart on: the connector starts at logon.'
        } else {
            Write-Host 'Autostart off: the connector no longer starts at logon. "mav-wifi start" still starts it now.'
        }
    }
    'config' {
        $config = Get-Config
        if (-not $Setting) {
            foreach ($key in $config.Keys) { Write-Host ('{0,-17}{1}' -f $key, $config[$key]) }
            Write-Host ''
            Write-Host "Config file: $ConfigFile"
            return
        }
        $name = $Defaults.Keys | Where-Object { $_ -eq $Setting }
        if (-not $name) {
            Write-Host "Unknown setting '$Setting'. Settings: $($Defaults.Keys -join ', ')"
            return
        }
        if (-not $Value) {
            Write-Host "$name = $($config[$name])"
            return
        }
        $parsed = ConvertTo-SettingValue $name $Value
        if ($null -eq $parsed) { return }
        $config[$name] = $parsed
        Save-Config $config
        Write-Host "$name = $parsed"
    }
    default {
        Write-Host "Unknown command '$Command'. Use: start, stop, status, log, autostart, config  (Get-Help mav-wifi)"
        return
    }
}
