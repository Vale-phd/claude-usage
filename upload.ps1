# Claude Code Usage Uploader — runs via Task Scheduler every 6 hours
# Uploads ccusage JSON to the team GitHub repo

$ErrorActionPreference = "Stop"

$configDir = Join-Path $env:USERPROFILE ".config\claude-usage"
$configFile = Join-Path $configDir "config.ps1"
$logFile = Join-Path $configDir "upload.log"

function Log($msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $msg"
}

# Load config
if (-not (Test-Path $configFile)) {
    Log "ERROR: Config file not found at $configFile"
    exit 1
}
. $configFile

# Get token
$tokenFile = Join-Path $configDir ".token"
if (Test-Path $tokenFile) {
    $token = (Get-Content $tokenFile -Raw).Trim()
} else {
    Log "ERROR: GitHub token not found"
    exit 1
}

$repo = "vale-phd/claude-usage"

# Run ccusage
Log "Running ccusage..."
try {
    $usageJson = npx ccusage@latest daily --json --offline 2>$null
    if (-not $usageJson) { throw "Empty output" }
} catch {
    Log "ERROR: ccusage failed - $_"
    exit 1
}

# Base64 encode
$bytes = [System.Text.Encoding]::UTF8.GetBytes($usageJson -join "`n")
$content = [Convert]::ToBase64String($bytes)

$filePath = "data/$displayName.json"
$headers = @{
    "Authorization" = "token $token"
    "Accept" = "application/vnd.github.v3+json"
}

# Check if file exists
$sha = $null
try {
    $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$filePath" -Headers $headers -Method Get
    $sha = $existing.sha
} catch {}

# Upload
$body = @{
    message = "usage: update $displayName $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    content = $content
}
if ($sha) { $body.sha = $sha }

try {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$filePath" `
        -Headers $headers -Method Put -Body ($body | ConvertTo-Json) -ContentType "application/json"
    Log "SUCCESS: Uploaded $filePath"
} catch {
    Log "ERROR: Upload failed - $_"
}
