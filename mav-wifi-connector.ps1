<#
Keeps the MAV on-board Wi-Fi logged in.

While connected to a MAVSTART network, it probes the Windows connectivity-test URL.
When the captive portal intercepts it, the portal's "accept terms" form is submitted
directly (the same POST the "Csatlakozas a halozathoz" button sends).

Settings come from mav-wifi.config.json next to this script and are reloaded when the file
changes. -NetworkPattern and -IntervalSeconds override them for one run.

  .\mav-wifi-connector.ps1          # run continuously
  .\mav-wifi-connector.ps1 -Once    # single check, for testing
  .\mav-wifi-connector.ps1 -Manual  # run even when Autostart is off (used by "mav-wifi start")
#>
param(
    [string]$NetworkPattern,
    [int]$IntervalSeconds,
    [switch]$Once,
    [switch]$Manual
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProbeUrl        = 'http://www.msftconnecttest.com/connecttest.txt'
$ProbeBody       = 'Microsoft Connect Test'
$DefaultLoginUrl = 'https://virtual-ip.instant.telekom.hu/login.html'
$RedirectUrl     = 'https://www.telekom.hu/vallalati-megoldasok/sztenderd-szolgaltatasok'
$LogFile         = Join-Path $PSScriptRoot 'mav-wifi-connector.log'
$ConfigFile      = Join-Path $PSScriptRoot 'mav-wifi.config.json'

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Write-Host $line
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
            Move-Item $LogFile "$LogFile.old" -Force
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {}
}

function Show-Notification([string]$Title, [string]$Text) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$Title</text><text>$Text</text></binding></visual></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {
        Write-Log "Notification failed: $($_.Exception.Message)"
    }
}

function Test-OnMavNetwork {
    [bool](Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $Config.NetworkPattern })
}

function Read-Config {
    $config = [ordered]@{ IntervalSeconds = 5; NetworkPattern = '^MAVSTART'; Autostart = $true }
    if (Test-Path $ConfigFile) {
        try {
            (Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties |
                Where-Object { $config.Contains($_.Name) } | ForEach-Object { $config[$_.Name] = $_.Value }
        } catch {
            Write-Log "Ignoring ${ConfigFile}: $($_.Exception.Message)"
        }
    }
    if ($NetworkPattern) { $config.NetworkPattern = $NetworkPattern }
    if ($IntervalSeconds -gt 0) { $config.IntervalSeconds = $IntervalSeconds }
    if ([int]$config.IntervalSeconds -lt 1) { $config.IntervalSeconds = 5 }
    $config
}

function Get-ConfigStamp {
    if (Test-Path $ConfigFile) { (Get-Item $ConfigFile).LastWriteTimeUtc.Ticks } else { 0 }
}

function Invoke-Http {
    param([string]$Url, [string]$Method = 'GET', [string]$Body, [string]$Referer)

    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.AllowAutoRedirect = $false
    $req.Timeout = 8000
    $req.ReadWriteTimeout = 8000
    $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    if ($Referer) { $req.Referer = $Referer }
    if ($Body) {
        $bytes = [Text.Encoding]::ASCII.GetBytes($Body)
        $req.ContentType = 'application/x-www-form-urlencoded'
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }

    try {
        $resp = $req.GetResponse()
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
        if (-not $ex -or -not $ex.Response) { throw }
        $resp = $ex.Response
    }
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        [pscustomobject]@{
            Status   = [int]$resp.StatusCode
            Location = $resp.Headers['Location']
            Body     = $reader.ReadToEnd()
        }
    } finally {
        $resp.Close()
    }
}

function Find-SwitchUrl([string]$Text) {
    if ($Text -match 'switch_url=([^&"''\s<>]+)') { return [Uri]::UnescapeDataString($Matches[1]) }
}

function Get-PortalState {
    try {
        $r = Invoke-Http $ProbeUrl
    } catch {
        return [pscustomobject]@{ State = 'NoNetwork' }
    }
    if ($r.Status -eq 200 -and $r.Body.Trim() -eq $ProbeBody) {
        return [pscustomobject]@{ State = 'Online' }
    }

    $portalUrl = $r.Location
    $loginUrl = Find-SwitchUrl "$($r.Location) $($r.Body)"
    if (-not $loginUrl -and $portalUrl) {
        try { $loginUrl = Find-SwitchUrl (Invoke-Http $portalUrl).Body } catch {}
    }
    if (-not $loginUrl) { $loginUrl = $DefaultLoginUrl }

    [pscustomobject]@{ State = 'Captive'; LoginUrl = $loginUrl; PortalUrl = $portalUrl }
}

function Submit-Login($Portal) {
    $body = 'buttonClicked=4&err_flag=0&redirect_url=' + [Uri]::EscapeDataString($RedirectUrl) + '&hfelt=1'
    try {
        $r = Invoke-Http -Url $Portal.LoginUrl -Method POST -Body $body -Referer $Portal.PortalUrl
    } catch {
        Write-Log "Login request failed: $($_.Exception.Message)"
        return $false
    }

    Start-Sleep -Seconds 2
    if ((Get-PortalState).State -eq 'Online') { return $true }

    $snippet = ($r.Body -replace '\s+', ' ')
    if ($snippet.Length -gt 300) { $snippet = $snippet.Substring(0, 300) }
    Write-Log "Still captive after login. Portal answered HTTP $($r.Status): $snippet"
    $false
}

$configStamp = Get-ConfigStamp
$Config = Read-Config
if (-not $Config.Autostart -and -not ($Once -or $Manual)) {
    Write-Log 'Not starting at logon: autostart is off ("mav-wifi autostart on" turns it back on).'
    return
}

$mutex = New-Object Threading.Mutex($false, 'Local\mav-wifi-connector')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'Already running.'
    return
}

Register-ObjectEvent -InputObject ([Net.NetworkInformation.NetworkChange]) -EventName NetworkAddressChanged `
    -SourceIdentifier NetChange | Out-Null

Write-Log "Started (network '$($Config.NetworkPattern)', on network change or every $($Config.IntervalSeconds) s)"
$lastState = ''
while ($true) {
    $stamp = Get-ConfigStamp
    if ($stamp -ne $configStamp) {
        $configStamp = $stamp
        $Config = Read-Config
        Write-Log "Config reloaded (network '$($Config.NetworkPattern)', every $($Config.IntervalSeconds) s)"
    }
    $state = 'NotOnMav'
    if (Test-OnMavNetwork) {
        $portal = Get-PortalState
        $state = $portal.State
        if ($state -eq 'Captive') {
            Write-Log "Captive portal detected, accepting via $($portal.LoginUrl)"
            if (Submit-Login $portal) {
                Write-Log 'Logged in.'
                Show-Notification 'MAV WiFi' 'Captive portal accepted automatically - you are back online.'
                $state = 'Online'
            }
        }
    }
    if ($state -ne $lastState) {
        Write-Log "State: $state"
        $lastState = $state
    }
    if ($Once) { break }
    if (Wait-Event -SourceIdentifier NetChange -Timeout $Config.IntervalSeconds) {
        Start-Sleep -Seconds 1
        Get-Event -SourceIdentifier NetChange -ErrorAction SilentlyContinue | Remove-Event
    }
}
