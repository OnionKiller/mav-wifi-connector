# mav-wifi-connector

A small Windows background tool that keeps you logged in to the MÁV (Hungarian railway) on-board Wi-Fi.

The train's Wi-Fi equipment restarts often, and after every restart the Telekom captive portal blocks traffic again until you find the login page and click **"Csatlakozás a hálózathoz"**. This tool notices that and accepts the portal for you, then shows a Windows notification.

## How it works

1. It checks whether you are connected to a `MAVSTART…` network. On any other network it does nothing.
2. On a MAV network it requests `http://www.msftconnecttest.com/connecttest.txt`, the same URL Windows uses to check internet access.
3. If the portal intercepts that request, the tool sends the portal's accept-terms form (`buttonClicked=4`, `hfelt=1`) directly to the login URL (`https://virtual-ip.instant.telekom.hu/login.html` by default, or the `switch_url` taken from the portal redirect). No browser is involved.
4. It checks again, logs the result, and shows a "back online" notification.

Checks run as soon as Windows reports a network change, and every 5 seconds as a fallback (for example when the portal session expires without the Wi-Fi dropping).

By running the tool you accept the portal's [terms of use](https://mav-fedelzet.instant.telekom.hu/szolgaltatasi_feltetelek.php) every time it logs you in.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in)

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

This registers a per-user scheduled task, **MAV WiFi Connector**, that starts hidden at every logon, and starts it right away. The task runs the script from this folder, so keep the folder where it is.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## Logs

State changes and logins are written to `mav-wifi-connector.log` next to the script. Once the log grows past 1 MB, it is moved to `mav-wifi-connector.log.old` and a new log is started.

```powershell
Get-Content .\mav-wifi-connector.log -Tail 20 -Wait
```

A successful automatic login looks like this:

```
2026-10-14 19:10:41  Captive portal detected, accepting via https://virtual-ip.instant.telekom.hu/login.html
2026-10-14 19:10:46  Logged in.
```

If the log shows `Still captive after login`, the line includes the portal's response, which helps when adjusting the form fields.

## Running manually

```powershell
.\mav-wifi-connector.ps1 -Once                  # single check, then exit
.\mav-wifi-connector.ps1 -IntervalSeconds 10    # change the fallback interval
.\mav-wifi-connector.ps1 -NetworkPattern '^MAV' # change the network-name regex
```

Only one instance runs at a time. A second copy exits with `Already running.`, so stop the scheduled task before you run the script by hand.
