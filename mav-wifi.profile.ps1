# Dot-source this from your PowerShell profile to get the mav-wifi command with tab completion and Get-Help.
# install.ps1 adds the line for you.
Set-Item function:global:mav-wifi (Get-Command (Join-Path $PSScriptRoot 'mav-wifi.ps1')).ScriptBlock
