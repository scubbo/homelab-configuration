#Requires -RunAsAdministrator
<#
Exposes the Open WebUI container (running in WSL2) on this Windows host's LAN
interface, so devices that resolve alpha.avril can reach http://alpha.avril:3000.

WSL2 uses a NAT'd IP that Windows only forwards from *localhost*, and that IP can
change across reboots. This re-derives the current IP and (re)creates the portproxy
plus an inbound firewall rule. Idempotent — re-run any time the UI stops being
reachable from the LAN (e.g. after a reboot changed the WSL IP).

Run from an ELEVATED PowerShell:
    powershell.exe -ExecutionPolicy Bypass -File .\expose-openwebui.ps1
#>
param([int]$Port = 3000)

# WSL eth0 IPv4 (avoids picking up docker bridge addresses that `hostname -I` also lists)
$wslIp = ((wsl.exe -- ip -4 -o addr show eth0) -join "`n").Trim() -replace '(?s).*inet\s+([\d.]+)/.*', '$1'
if ($wslIp -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Error "Couldn't determine WSL eth0 IP (got '$wslIp'). Is WSL running?"; exit 1
}

netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add    v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$wslIp

$rule = "WSL Open WebUI ($Port)"
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
}

Write-Host "OK: LAN 0.0.0.0:$Port -> WSL ${wslIp}:$Port  (firewall rule '$rule' ensured)"
Write-Host "Reach it at http://alpha.avril:$Port once the alpha.avril DNSEndpoint is live."
