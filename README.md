# mav-wifi-connector

A small Windows background tool that keeps you logged in to the MÁV (Hungarian railway) on-board Wi-Fi.

The train's Wi-Fi equipment restarts often, and after every restart the Telekom captive portal blocks traffic again until you find the login page and click **"Csatlakozás a hálózathoz"**. This tool notices that and accepts the portal for you, then shows a Windows notification.

## How it works

1. It checks whether you are connected to a `MAVSTART…` network. On any other network it does nothing.
2. On a MAV network it requests `http://www.msftconnecttest.com/connecttest.txt`, the same URL Windows uses to check internet access.
3. If the portal intercepts that request, the tool sends the portal's accept-terms form (`buttonClicked=4`, `hfelt=1`) directly to the login URL (`https://virtual-ip.instant.telekom.hu/login.html` by default, or the `switch_url` taken from the portal redirect). No browser is involved.
4. It checks again, logs the result, and shows a "back online" notification.

Checks run as soon as Windows reports a network change, and every 5 seconds as a fallback (for example when the portal session expires without the Wi-Fi dropping). The interval is configurable, see [Configuration](#configuration).

By running the tool you accept the portal's [terms of use](https://mav-fedelzet.instant.telekom.hu/szolgaltatasi_feltetelek.php) every time it logs you in.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in)

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

This registers a per-user scheduled task, **MAV WiFi Connector**, that starts hidden at every logon, and starts it right away. The task runs the script from this folder, so keep the folder where it is.

It also sets up the `mav-wifi` command:

- adds `bin\` (which holds only `mav-wifi.cmd`) to your user `PATH`, so the command works in cmd and other shells;
- adds one guarded line to your PowerShell profile that dot-sources `mav-wifi.profile.ps1`. In PowerShell, `mav-wifi` then has tab completion with a description for each command, and `Get-Help mav-wifi` works. The line does nothing on a machine where this folder doesn't exist.

To set up only the command and leave the task alone, run `.\install.ps1 -CommandOnly`. Running the installer again is safe. Open a new terminal afterwards.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This removes the task, the `PATH` entry and the profile line.

## The mav-wifi command

```powershell
mav-wifi start                      # start it now
mav-wifi start -NoConsole           # start it now directly, with no console window at all
mav-wifi stop                       # stop it now (it starts again at the next logon unless autostart is off)
mav-wifi status                     # running?, starts at logon?, check interval, network pattern
mav-wifi log                        # show the last 20 log lines
mav-wifi log -Lines 50              # show the last 50 log lines
mav-wifi log -Follow                # keep printing new log lines (Ctrl+C to quit)
mav-wifi autostart off              # don't start at logon (autostart on: start at logon again)
mav-wifi config                     # show all settings and the config file path
mav-wifi config IntervalSeconds 30  # change a setting
```

In PowerShell, press Tab after `mav-wifi ` to cycle through the commands, setting names and values, or Ctrl+Space to see them all with descriptions. `Get-Help mav-wifi` describes every command, and `Get-Help mav-wifi -Examples` lists examples.

`mav-wifi start` goes through the scheduled task. With `-NoConsole`, when autostart is off, or when the task isn't installed, it runs the connector directly in a headless console (`conhost.exe --headless`) instead.

The PowerShell `mav-wifi` function is loaded from `mav-wifi.ps1` when the terminal starts, so after editing that script, open a new terminal to pick up the change.

## Configuration

Settings live in `mav-wifi.config.json` next to the scripts:

```json
{
  "IntervalSeconds": 5,
  "NetworkPattern": "^MAVSTART",
  "Autostart": true
}
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `IntervalSeconds` | `5` | Seconds between internet checks. A check also runs right away whenever Windows reports a network change. |
| `NetworkPattern` | `^MAVSTART` | Regex for the Wi-Fi names to act on. On other networks the connector does nothing. |
| `Autostart` | `true` | Start the connector at logon. `mav-wifi autostart on/off` sets this. |

Change them with `mav-wifi config <name> <value>` (it checks the value) or edit the file by hand. A running connector reloads the file at its next check and logs `Config reloaded`. Missing settings fall back to the defaults.

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
.\mav-wifi-connector.ps1 -IntervalSeconds 10    # override the config interval for this run
.\mav-wifi-connector.ps1 -NetworkPattern '^MAV' # override the config network regex for this run
.\mav-wifi-connector.ps1 -Manual                # run even when Autostart is off
```

Only one instance runs at a time. A second copy exits with `Already running.`, so run `mav-wifi stop` before you run the script by hand.
