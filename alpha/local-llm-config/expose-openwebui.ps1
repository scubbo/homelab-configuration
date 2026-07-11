#Requires -RunAsAdministrator
<#
Exposes the Open WebUI container (running in WSL2) on this Windows host's LOCAL
NETWORK only, so devices on the LAN can reach http://alpha.avril:3000.

Access is restricted two independent ways:
  1. the proxy binds to this host's LAN IP, so it never listens on other
     interfaces (e.g. a Tailscale adapter); and
  2. the inbound firewall rule admits only source addresses on $LanCidr.
Other interfaces and the public internet get nothing. (The internet can't reach
it regardless — this touches only the host, not the router; there is no
port-forward.)

WSL2 uses a NAT'd IP that Windows only forwards from localhost, and that IP can
change across reboots. This re-derives it and (re)creates the portproxy + rule.
Idempotent — re-run any time the UI stops being reachable from the LAN.

Run from an ELEVATED PowerShell:
    powershell.exe -ExecutionPolicy Bypass -File .\expose-openwebui.ps1
#>
param(
    [int]$Port = 3000,
    [string]$LanCidr = "192.168.1.0/24"   # ONLY devices on this subnet may connect
)

# WSL eth0 IPv4 (avoids docker bridge addresses that `hostname -I` also lists)
$wslIp = ((wsl.exe -- ip -4 -o addr show eth0) -join "`n").Trim() -replace '(?s).*inet\s+([\d.]+)/.*', '$1'
if ($wslIp -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Error "Couldn't determine WSL eth0 IP (got '$wslIp'). Is WSL running?"; exit 1
}

# This host's IPv4 on the LAN subnet. Binding the proxy here keeps it off every
# other interface (Tailscale, VPNs). Falls back to 0.0.0.0 (firewall still scopes).
$lanPrefix = (($LanCidr -split '/')[0] -replace '\.\d+$', '.')
$listen = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -like "$lanPrefix*" } | Select-Object -First 1).IPAddress
if (-not $listen) { $listen = "0.0.0.0" }

# Clear any prior proxy for this port (including a permissive 0.0.0.0 one), then set ours.
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=$listen  2>$null | Out-Null
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0  2>$null | Out-Null
netsh interface portproxy add    v4tov4 listenport=$Port listenaddress=$listen connectport=$Port connectaddress=$wslIp

# Recreate the firewall rule each run so its scope is always current (LAN subnet only).
$rule = "WSL Open WebUI ($Port)"
Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP `
    -LocalPort $Port -RemoteAddress $LanCidr | Out-Null

Write-Host "OK: ${listen}:$Port -> WSL ${wslIp}:$Port   (inbound allowed only from $LanCidr)"
Write-Host "Reach it at http://alpha.avril:$Port from a device on that subnet."
