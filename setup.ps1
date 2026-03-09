# Claude Code Usage — Team Onboarding (Windows)
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Usage - Team Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Get display name
$displayName = Read-Host "Enter your display name (e.g. john)"
$displayName = $displayName.ToLower().Replace(" ", "-")

# 2. Get GitHub token
Write-Host ""
Write-Host "You need a GitHub Personal Access Token (classic) with 'repo' scope."
Write-Host "Create one at: https://github.com/settings/tokens/new"
Write-Host "  - Note: claude-usage"
Write-Host "  - Expiration: No expiration (or 1 year)"
Write-Host "  - Scope: check 'repo'"
Write-Host ""
$secureToken = Read-Host "Paste your GitHub token" -AsSecureString
$token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))

# 3. Verify token
Write-Host "Verifying token..."
try {
    $headers = @{ "Authorization" = "token $token"; "Accept" = "application/vnd.github.v3+json" }
    Invoke-RestMethod -Uri "https://api.github.com/repos/vale-phd/claude-usage" -Headers $headers | Out-Null
    Write-Host "Token verified!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Token doesn't have access to vale-phd/claude-usage" -ForegroundColor Red
    exit 1
}

# 4. Store config
$configDir = Join-Path $env:USERPROFILE ".config\claude-usage"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

@"
`$displayName = "$displayName"
"@ | Set-Content (Join-Path $configDir "config.ps1")

# 5. Store token
$token | Set-Content (Join-Path $configDir ".token")
$tokenPath = Join-Path $configDir ".token"
$acl = Get-Acl $tokenPath
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $env:USERNAME, "FullControl", "Allow")
$acl.SetAccessRule($rule)
Set-Acl $tokenPath $acl
Write-Host "Token stored securely."

# 6. Download upload script
$uploadUrl = "https://raw.githubusercontent.com/vale-phd/claude-usage/main/upload.ps1"
Invoke-WebRequest -Uri $uploadUrl -OutFile (Join-Path $configDir "upload.ps1")

# 7. Check dependencies
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "WARNING: Node.js is not installed. ccusage needs npx." -ForegroundColor Yellow
    Write-Host "Install from: https://nodejs.org/"
}

# 8. Install scheduled task (every 6 hours)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -File `"$configDir\upload.ps1`""
$triggers = @(
    New-ScheduledTaskTrigger -Daily -At "00:00"
    New-ScheduledTaskTrigger -Daily -At "06:00"
    New-ScheduledTaskTrigger -Daily -At "12:00"
    New-ScheduledTaskTrigger -Daily -At "18:00"
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable
Register-ScheduledTask -TaskName "ClaudeUsageUpload" -Action $action `
    -Trigger $triggers -Settings $settings -Force | Out-Null
Write-Host "Scheduled task installed (every 6 hours)."

# 9. Run first upload
Write-Host ""
Write-Host "Running first upload..."
& (Join-Path $configDir "upload.ps1")

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  Dashboard: https://vale-phd.github.io/claude-usage/" -ForegroundColor Green
Write-Host "  Logs: $configDir\upload.log" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
