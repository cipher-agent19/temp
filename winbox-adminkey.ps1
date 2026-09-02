# winbox-adminkey.ps1
# Fixes Windows OpenSSH administrator-key quirk: puts the Hermes key where
# a member of the Administrators group is actually read from, with correct ACL.
# Run in an ADMIN PowerShell on the laptop.
# Author: cipher (hermes agent)
$ErrorActionPreference = "Continue"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "[FAIL] Run as Administrator." -ForegroundColor Red; exit 1 }

# Who are we (for reference only)
$me = whoami
Write-Host "Running as: $me" -ForegroundColor Cyan

$SSHKEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkYA6dt4dh40mER04hu00KZPa8QI/j2ZZHgWm0Wcwkn hermes@winbox"

# 1. Write to the admin shared key file (ProgramData)
$adminKeyDir = "$env:ProgramData\ssh"
$adminKeyFile = Join-Path $adminKeyDir "administrators_authorized_keys"
if (-not (Test-Path $adminKeyDir)) { New-Item -ItemType Directory -Path $adminKeyDir -Force | Out-Null }

$already = $false
if (Test-Path $adminKeyFile) { $already = (Select-String -Path $adminKeyFile -Pattern "hermes@winbox" -Quiet) }
if (-not $already) {
    Set-Content -Path $adminKeyFile -Value $SSHKEY
    Write-Host "  wrote $adminKeyFile" -ForegroundColor Green
} else {
    Write-Host "  key already present in $adminKeyFile" -ForegroundColor Green
}

# 2. Fix ACLs - MUST be SYSTEM + Administrators only, else sshd ignores it
$acl = Get-Acl $adminKeyFile
$acl.SetAccessRuleProtection($true, $false)
$system = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM","FullControl","Allow")
$admins = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")
$acl.AddAccessRule($system)
$acl.AddAccessRule($admins)
Set-Acl $adminKeyFile $acl
Write-Host "  ACL set (SYSTEM + Administrators only)" -ForegroundColor Green

# 3. Also make sure sshd is running + restart to reload config
Get-Service sshd -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic -ErrorAction SilentlyContinue
Restart-Service sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "  sshd restarted" -ForegroundColor Green

Write-Host ""
Write-Host "DONE. Tell Hermes to try again." -ForegroundColor Cyan
