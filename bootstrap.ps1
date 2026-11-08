# One-line bootstrap for a remote Windows 11 laptop:
# enables OpenSSH server (key-only) for JARVIS over Tailscale.
# Safe to run twice.

$src = 'https://sitechfromgeorgia.github.io/windows11-legion-guide/bootstrap.ps1'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ''
    Write-Host '  ახლა გამოჩნდება Windows-ის კითხვა (UAC). დააჭირე "Yes".' -ForegroundColor Yellow
    Write-Host ''
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',"irm $src | iex")
    Start-Sleep 3
    exit
}

$ErrorActionPreference = 'Continue'
Write-Host ''
Write-Host '  Setup started. This takes 1-3 minutes...' -ForegroundColor Cyan

$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAWPYS3tVy29OJGLWjRGeEp7YHWNj5x14t212pTnmbYf jarvis-tekla'

# --- 1. OpenSSH server from GitHub (no Windows Update needed) ---
$zip = Join-Path $env:TEMP 'OpenSSH-Win64.zip'
$ext = Join-Path $env:TEMP 'OpenSSH-extract'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip' -OutFile $zip -UseBasicParsing -TimeoutSec 300
    Write-Host '  OpenSSH downloaded' -ForegroundColor Green
} catch {
    Write-Host ('  download failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '  check internet and run the line again' -ForegroundColor Yellow
    Start-Sleep 20
    exit 1
}

if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $ext -Force
$inner = (Get-ChildItem $ext -Directory | Select-Object -First 1).FullName
$dest = 'C:\Program Files\OpenSSH'
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
Copy-Item (Join-Path $inner '*') $dest -Recurse -Force
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install-sshd.ps1')
Write-Host '  OpenSSH installed' -ForegroundColor Green

# --- 2. service + config ---
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -Value 0 -Type DWord

$cfg = Join-Path $dest 'sshd_config'
if (Test-Path $cfg) {
    $lines = Get-Content $cfg | Where-Object { $_ -notmatch '^\s*(PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords)\s+' }
    $lines += 'PubkeyAuthentication yes'
    $lines += 'PasswordAuthentication no'
    $lines += 'PermitEmptyPasswords no'
    Set-Content -Path $cfg -Value $lines
}

# --- 3. authorized keys ---
$keyDir = 'C:\ProgramData\ssh'
if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir -Force | Out-Null }
$ak = Join-Path $keyDir 'administrators_authorized_keys'
if (-not (Test-Path $ak) -or -not ((Get-Content $ak) -match 'jarvis-tekla')) { Add-Content -Path $ak -Value $pub -Encoding ascii }
& icacls.exe $ak /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

$userDir = 'C:\Users\' + $env:USERNAME + '\.ssh'
if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Path $userDir -Force | Out-Null }
$uk = Join-Path $userDir 'authorized_keys'
if (-not (Test-Path $uk) -or -not ((Get-Content $uk) -match 'jarvis-tekla')) { Add-Content -Path $uk -Value $pub -Encoding ascii }
Write-Host '  access key installed' -ForegroundColor Green

# --- 4. firewall + restart ---
if (-not (Get-NetFirewallRule -DisplayName 'OpenSSH Server (TCP 22)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'OpenSSH Server (TCP 22)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
}
Restart-Service sshd
Start-Sleep 3

$svc = Get-Service sshd
$listen = (netstat -ano | Select-String ':22\s' | Select-Object -First 1)
Write-Host ''
Write-Host ('  sshd: ' + $svc.Status) -ForegroundColor Green
if ($listen) { Write-Host '  port 22 is listening' -ForegroundColor Green } else { Write-Host '  port 22 NOT listening' -ForegroundColor Red }
Write-Host ''
Write-Host '  DONE. You can close this window.' -ForegroundColor Cyan
Write-Host ('  computer: ' + $env:COMPUTERNAME + ' | user: ' + $env:USERNAME)
Start-Sleep 25
