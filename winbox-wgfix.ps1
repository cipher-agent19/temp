# winbox-wgfix.ps1
# Idempotent WireGuard repair for the winbox (10.7.0.6) mesh tunnel.
# Run in an ADMIN PowerShell. Fixes: WG not installed, tunnel service missing/stopped, config missing.
# Publishes WG public key + tunnel status so Hermes can confirm the handshake.
# Author: cipher (hermes agent)
$ErrorActionPreference = "Continue"
function Write-Step { param([string]$m) Write-Host ("`n== " + $m) -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host ("  [ok] " + $m) -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host ("  [!] " + $m) -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "[FAIL] Run as Administrator." -ForegroundColor Red; exit 1 }

$confPath = "$env:ProgramData\WireGuard\winbox.conf"
$wgExe    = "C:\Program Files\WireGuard\wireguard.exe"
$wgCli    = "C:\Program Files\WireGuard\wg.exe"

# ---- 1. Ensure WireGuard is installed ----
Write-Step "1. Ensure WireGuard installed"
if (-not (Test-Path $wgExe)) {
    Write-Warn "WireGuard not found. Attempting install via winget..."
    winget install --id WireGuard.WireGuard --exact --silent --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Host
    Start-Sleep -Seconds 5
}
if (-not (Test-Path $wgExe)) {
    # Fallback: direct silent installer (WireGuard official EXE)
    Write-Warn "winget did not work. Trying official installer..."
    try {
        Invoke-WebRequest -Uri "https://download.wireguard.com/windows-client/wireguard-installer.exe" -OutFile "$env:TEMP\wg-installer.exe" -UseBasicParsing
        Start-Process -FilePath "$env:TEMP\wg-installer.exe" -ArgumentList "/quiet" -Wait
        Start-Sleep -Seconds 5
    } catch { Write-Warn "Installer download/run failed: $_" }
}
if (Test-Path $wgExe) { Write-Ok "WireGuard present: $wgExe" } else { Write-Host "[FAIL] WireGuard still not installed. Manual needed: https://www.wireguard.com/install/" -ForegroundColor Red; exit 2 }

# ---- 2. Ensure config exists ----
Write-Step "2. Ensure winbox.conf exists"
if (-not (Test-Path $confPath)) {
    Write-Warn "Config missing. Generating fresh (keeping any existing keypair if present)..."
    $priv = (& $wgCli genkey).Trim()
    $pub  = ($priv | & $wgCli pubkey).Trim()
    Write-Host "  NEW PUBLIC KEY=$pub" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path (Split-Path $confPath) -Force | Out-Null
    Set-Content -Path $confPath -Value @"
[Interface]
PrivateKey = $priv
Address = 10.7.0.6/24
DNS = 10.7.0.1

[Peer]
PublicKey = draVsFkv4hzkEQ8qE/EEthJLJXyGenSGa7WzrGY3mHA=
Endpoint = 68.168.222.151:51820
AllowedIPs = 10.7.0.0/24
PersistentKeepalive = 25
"@
    Write-Warn "New keypair generated. THIS PUBLIC KEY ($pub) MUST be sent to Hermes - it differs from any prior key."
} else {
    Write-Ok "winbox.conf exists"
}

# ---- 3. Install/start the tunnel service ----
Write-Step "3. Tunnel service"
$svcName = 'WireGuardTunnel$winbox'
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Warn "Service missing - installing headless tunnel service..."
    & $wgExe /installtunnelservice $confPath
    Start-Sleep -Seconds 4
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
}
if ($svc) {
    Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
    if ($svc.Status -ne "Running") { Start-Service -Name $svcName -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 4
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    Write-Ok "Tunnel service: $($svc.Status) (startup=Automatic)"
} else {
    Write-Host "[FAIL] Could not install tunnel service '$svcName'." -ForegroundColor Red
}

# ---- 4. Report ---- 
Write-Step "4. Status"
$pubkey = "?"
if (Test-Path $confPath) {
    $confTxt = Get-Content $confPath -Raw
    if ($confTxt -match "PrivateKey = (\S+)") {
        $pubkey = (("$($matches[1])") | & $wgCli pubkey).Trim()
    }
}
Write-Host ""
Write-Host " FORWARD THIS LINE TO HERMES:" -ForegroundColor Yellow
Write-Host ("  WINBOX_WG_PUBKEY=" + $pubkey) -ForegroundColor Yellow
Write-Host ""
if (Test-Path $wgCli) {
    Write-Host "--- wg show ---"
    & $wgCli show
}
