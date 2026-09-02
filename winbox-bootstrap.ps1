# winbox-bootstrap.ps1
# One-shot bootstrap to hand my (Hermes) admin SSH access to this Windows machine
# and join it to the existing WireGuard mesh as 10.7.0.6.
# Run in an ADMIN PowerShell. Nothing here contains secret material.
# Author: cipher (hermes agent) via cipher-agent19/temp
# Generated: 2026-09-02

$ErrorActionPreference = "Continue"
$scriptStart = Get-Date

function Write-Step { param([string]$m) Write-Host ("`n== " + $m) -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host ("  [ok] " + $m) -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host ("  [!] " + $m) -ForegroundColor Yellow }

Write-Host "==============================================" -ForegroundColor Magenta
Write-Host " hermebox winbox bootstrap" -ForegroundColor Magenta
Write-Host "==============================================" -ForegroundColor Magenta

# 0. Elevation check (must be Administrator)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[FAIL] PowerShell must be running as Administrator. Right-click the PS icon > 'Run as administrator'." -ForegroundColor Red
    exit 1
}
Write-Ok "Running elevated"

# 1. Mesh constants (public values, no secrets)
$WG_IFACE_NAME   = "winbox"
$WG_ADDR         = "10.7.0.6/24"
$WG_DNS          = "10.7.0.1"
$WG_ENDPOINT     = "68.168.222.151:51820"
$WG_HUB_PUBKEY   = "draVsFkv4hzkEQ8qE/EEthJLJXyGenSGa7WzrGY3mHA="
$WG_ALLOWED_IPS  = "10.7.0.0/24"
$WG_KEEPALIVE    = "25"
$SSH_PUB_KEY     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkYA6dt4dh40mER04hu00KZPa8QI/j2ZZHgWm0Wcwkn hermes@winbox"

# 2. OpenSSH Server install
Write-Step "Installing / enabling Windows OpenSSH Server"
$sshSvc = Get-Service -Name sshd -ErrorAction SilentlyContinue
if (-not $sshSvc) {
    Write-Host "  Attempting Microsoft OpenSSH capability install..." 
    $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue
    if ($cap.State -ne "Installed") {
        try { Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction Stop | Out-Null }
        catch {
            Write-Warn "Add-WindowsCapability failed. Trying winget Microsoft.OpenSSH."
            try { winget install --id Microsoft.OpenSSH.Beta --accept-source-agreements --accept-package-agreements --silent -e | Out-Null }
            catch { Write-Warn "winget install OpenSSH also failed. Continuing (may need manual sshd install)." }
        }
    }
    $sshSvc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($sshSvc) {
        Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service sshd -ErrorAction SilentlyContinue
        Write-Ok "sshd service started + set to Automatic"
    } else {
        Write-Warn "sshd service not found after install attempt"
    }
} else {
    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service sshd -ErrorAction SilentlyContinue
    Write-Ok "sshd already present, set Automatic + started"
}

# 2b. Grant the current admin user's pubkey for key auth
Write-Step "Installing admin SSH public key"
$sshDir  = Join-Path $env:USERPROFILE ".ssh"
$authKey = Join-Path $sshDir "authorized_keys"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
$already = $false
if (Test-Path $authKey) {
    $already = (Select-String -Path $authKey -Pattern "hermes@winbox" -Quiet)
}
if (-not $already) {
    Add-Content -Path $authKey -Value $SSH_PUB_KEY
    Write-Ok "Added hermes public key to $authKey"
} else {
    Write-Ok "hermes key already present"
}
# Ensure sshd allows pubkey + admin
$sshdCfg = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdCfg) {
    $txt = Get-Content $sshdCfg -Raw
    if ($txt -notmatch "PubkeyAuthentication yes") { Add-Content $sshdCfg "`nPubkeyAuthentication yes" }
    if ($txt -notmatch "PasswordAuthentication")   { Add-Content $sshdCfg "PasswordAuthentication no" }
    restart-service sshd -Force -ErrorAction SilentlyContinue
    Write-Ok "sshd_config ensures pubkey; restarted"
}

# 2c. Firewall rule for 22 (OpenSSH server adds it normally; ensure it)
if (Get-Command "New-NetFirewallRule" -ErrorAction SilentlyContinue) {
    if (-not (Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-Ok "Firewall allow rule for TCP/22 added"
    } else { Write-Ok "Firewall rule already present" }
}

# 3. WireGuard install (headless tunnel service)
Write-Step "Installing WireGuard (headless service)"
$wgExe  = "C:\Program Files\WireGuard\wireguard.exe"
$wgCli  = "C:\Program Files\WireGuard\wg.exe"
if (-not (Test-Path $wgExe)) {
    try {
        winget install --id WireGuard.WireGuard --accept-source-agreements --accept-package-agreements --silent -e | Out-Null
    } catch { Write-Warn "winget WireGuard failed." }
}
if (-not (Test-Path $wgExe)) {
    $cand = Get-ChildItem "C:\Program Files\WireGuard\wireguard.exe" -ErrorAction SilentlyContinue
    if ($cand) { $wgExe = $cand.FullName }
}
if (Test-Path $wgExe) { Write-Ok "WireGuard present: $wgExe" } else {
    Write-Warn "WireGuard not installed - you may need to run winget install WireGuard.WireGuard first."
}

# 3b. Generate WireGuard keypair locally
Write-Step "Generating WireGuard keys"
$wgKey = $null
if (Test-Path $wgCli) {
    $priv = (& $wgCli genkey).Trim()
    $pub  = ($priv | & $wgCli pubkey).Trim()
    Write-Ok "WG keypair generated locally (private key never leaves this machine)"
} else {
    Write-Warn "wg.exe not found; cannot generate keys. Skipping WG config."
}

if ($priv) {
    $conf = @"
[Interface]
PrivateKey = $priv
Address = $WG_ADDR
DNS = $WG_DNS

[Peer]
PublicKey = $WG_HUB_PUBKEY
Endpoint = $WG_ENDPOINT
AllowedIPs = $WG_ALLOWED_IPS
PersistentKeepalive = $WG_KEEPALIVE
"@
    $confPath = "$env:ProgramData\WireGuard\winbox.conf"
    New-Item -ItemType Directory -Path (Split-Path $confPath) -Force | Out-Null
    Set-Content -Path $confPath -Value $conf
    Write-Ok "WG config written: $confPath"

    # 3c. Install as a headless Windows service (auto-start at boot, no login)
    Write-Step "Installing WireGuard tunnel service (auto-start)"
    $svcName = "WireGuardTunnel`$$WG_IFACE_NAME"
    $existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $existing) {
        try {
            & $wgExe /installtunnelservice $confPath | Out-Null
            Start-Sleep -Seconds 3
            Write-Ok "Installed + started WireGuard tunnel service '$svcName'"
        } catch { Write-Warn "Could not install tunnel service. Error: $_" }
    } else {
        Write-Ok "Tunnel service already exists"
    }
}

# 4. Summary - the ONE thing to forward to me
Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " BOOTSTRAP COMPLETE" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ("Mesh IP : " + $WG_ADDR)
Write-Host ("sshd    : " + ((Get-Service -Name sshd -ErrorAction SilentlyContinue).Status) + " (Auto)")
if ($priv) {
    Write-Host ""
    Write-Host " FORWARD THIS LINE TO HERMES:" -ForegroundColor Yellow
    Write-Host ("  WINBOX_WG_PUBKEY=" + $pub) -ForegroundColor Yellow
    Write-Host ""
}
Write-Host ("Elapsed: " + ((Get-Date) - $scriptStart).TotalSeconds + "s")
