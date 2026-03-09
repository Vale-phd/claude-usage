# Team Claude Code Usage Dashboard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A GitHub Pages dashboard where ~10 team members automatically upload their Claude Code usage data every 6 hours, with a main page showing all users and drill-down views per user with historical data.

**Architecture:** Each team member runs a platform-native scheduled task (cron on macOS/Linux, Task Scheduler on Windows) that calls `npx ccusage@latest daily --json` and uploads the result to a GitHub repo via the GitHub API. A GitHub Action merges incoming data into monthly archive files so history persists even after local JSONL files are deleted. A static single-page dashboard (HTML/CSS/JS + Chart.js) served by GitHub Pages reads the JSON files and renders the UI.

**Tech Stack:** Vanilla HTML/CSS/JS, Chart.js (CDN), GitHub Pages, GitHub Actions, Bash, PowerShell, GitHub REST API.

**GitHub repo:** `vale-phd/claude-usage` (public for now, move to private lab GitHub later)

---

## Task 1: Create GitHub Repo and Base Structure

**Files:**
- Create: `README.md`
- Create: `data/.gitkeep`
- Create: `history/.gitkeep`

**Step 1: Initialize local git repo**

```bash
cd /Users/vromanov/Documents/Imperial/Projects/Submitted/LLMs+PromptEngineering-2025/Figures/Figure8/claude-usage
git init
```

**Step 2: Create directory structure**

```bash
mkdir -p data history .github/workflows
touch data/.gitkeep history/.gitkeep
```

**Step 3: Create README.md**

```markdown
# Claude Code Team Usage Dashboard

Automated usage tracking for the team. Each member's machine uploads usage data every 6 hours.

## Onboarding

**macOS / Linux:**
```bash
bash <(curl -sL https://vale-phd.github.io/claude-usage/setup.sh)
```

**Windows (PowerShell as Admin):**
```powershell
irm https://vale-phd.github.io/claude-usage/setup.ps1 | iex
```

## Dashboard

Visit: https://vale-phd.github.io/claude-usage/
```

**Step 4: Initial commit**

```bash
git add -A
git commit -m "feat: initialize repo structure"
```

---

## Task 2: Build the Upload Scripts

These are the scripts that run every 6 hours on each team member's machine. They call ccusage, then upload the JSON to the GitHub repo via the API.

**Files:**
- Create: `upload.sh` (macOS/Linux)
- Create: `upload.ps1` (Windows)

**Step 1: Create upload.sh**

```bash
#!/bin/bash
# Claude Code Usage Uploader — runs via cron every 6 hours
# Uploads ccusage JSON to the team GitHub repo

set -euo pipefail

CONFIG_DIR="$HOME/.config/claude-usage"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/upload.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

# Get token
get_token() {
    if command -v security &>/dev/null; then
        security find-generic-password -s "claude-usage-token" -w 2>/dev/null
    else
        cat "$CONFIG_DIR/.token" 2>/dev/null
    fi
}

GITHUB_TOKEN=$(get_token)
if [ -z "$GITHUB_TOKEN" ]; then
    log "ERROR: GitHub token not found"
    exit 1
fi

REPO="vale-phd/claude-usage"

# Run ccusage
log "Running ccusage..."
USAGE_JSON=$(npx ccusage@latest daily --json --offline 2>/dev/null) || {
    log "ERROR: ccusage failed"
    exit 1
}

# Base64 encode for GitHub API
CONTENT=$(echo "$USAGE_JSON" | base64)

# Check if file exists (to get SHA for update)
FILE_PATH="data/${DISPLAY_NAME}.json"
EXISTING=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/contents/$FILE_PATH" 2>/dev/null)

SHA=$(echo "$EXISTING" | grep '"sha"' | head -1 | sed 's/.*"sha": "\(.*\)".*/\1/')

# Upload
if [ -n "$SHA" ]; then
    # Update existing file
    PAYLOAD=$(cat <<HEREDOC
{
  "message": "usage: update ${DISPLAY_NAME} $(date '+%Y-%m-%d %H:%M')",
  "content": "$CONTENT",
  "sha": "$SHA"
}
HEREDOC
)
else
    # Create new file
    PAYLOAD=$(cat <<HEREDOC
{
  "message": "usage: add ${DISPLAY_NAME} $(date '+%Y-%m-%d %H:%M')",
  "content": "$CONTENT"
}
HEREDOC
)
fi

RESPONSE=$(curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/contents/$FILE_PATH" \
    -d "$PAYLOAD" 2>/dev/null)

if echo "$RESPONSE" | grep -q '"content"'; then
    log "SUCCESS: Uploaded $FILE_PATH"
else
    log "ERROR: Upload failed — $RESPONSE"
fi
```

**Step 2: Create upload.ps1**

```powershell
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

# Get token from Windows Credential Manager
try {
    $cred = Get-StoredCredential -Target "claude-usage-token" -ErrorAction Stop
    $token = $cred.GetNetworkCredential().Password
} catch {
    # Fallback to file
    $tokenFile = Join-Path $configDir ".token"
    if (Test-Path $tokenFile) {
        $token = Get-Content $tokenFile -Raw
    } else {
        Log "ERROR: GitHub token not found"
        exit 1
    }
}

$repo = "vale-phd/claude-usage"

# Run ccusage
Log "Running ccusage..."
try {
    $usageJson = npx ccusage@latest daily --json --offline 2>$null
} catch {
    Log "ERROR: ccusage failed"
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
try {
    $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$filePath" -Headers $headers -Method Get
    $sha = $existing.sha
} catch {
    $sha = $null
}

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
    Log "ERROR: Upload failed — $_"
}
```

**Step 3: Commit**

```bash
git add upload.sh upload.ps1
git commit -m "feat: add cross-platform upload scripts"
```

---

## Task 3: Build the Onboarding Scripts

These are one-time setup scripts that team members run to configure their machine.

**Files:**
- Create: `setup.sh` (macOS/Linux)
- Create: `setup.ps1` (Windows)

**Step 1: Create setup.sh**

```bash
#!/bin/bash
# Claude Code Usage — Team Onboarding (macOS / Linux)
set -euo pipefail

echo "========================================"
echo "  Claude Code Usage — Team Setup"
echo "========================================"
echo ""

# 1. Get display name
read -p "Enter your display name (e.g. john): " DISPLAY_NAME
DISPLAY_NAME=$(echo "$DISPLAY_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# 2. Get GitHub token
echo ""
echo "You need a GitHub Personal Access Token (classic) with 'repo' scope."
echo "Create one at: https://github.com/settings/tokens/new"
echo "  - Note: claude-usage"
echo "  - Expiration: No expiration (or 1 year)"
echo "  - Scope: check 'repo'"
echo ""
read -sp "Paste your GitHub token: " GITHUB_TOKEN
echo ""

# 3. Verify token works
echo "Verifying token..."
VERIFY=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/vale-phd/claude-usage" 2>/dev/null)
if echo "$VERIFY" | grep -q '"full_name"'; then
    echo "Token verified!"
else
    echo "ERROR: Token doesn't have access to vale-phd/claude-usage"
    echo "Make sure you have repo scope and the repo exists."
    exit 1
fi

# 4. Store config
CONFIG_DIR="$HOME/.config/claude-usage"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

cat > "$CONFIG_DIR/config" <<EOF
DISPLAY_NAME="$DISPLAY_NAME"
EOF

# 5. Store token securely
if command -v security &>/dev/null; then
    # macOS Keychain
    security delete-generic-password -s "claude-usage-token" 2>/dev/null || true
    security add-generic-password -s "claude-usage-token" -a "$USER" -w "$GITHUB_TOKEN"
    echo "Token stored in macOS Keychain."
else
    # Linux — file with restricted permissions
    echo "$GITHUB_TOKEN" > "$CONFIG_DIR/.token"
    chmod 600 "$CONFIG_DIR/.token"
    echo "Token stored in $CONFIG_DIR/.token (chmod 600)."
fi

# 6. Download upload script
curl -sL "https://raw.githubusercontent.com/vale-phd/claude-usage/main/upload.sh" \
    -o "$CONFIG_DIR/upload.sh"
chmod +x "$CONFIG_DIR/upload.sh"

# 7. Check dependencies
if ! command -v node &>/dev/null && ! command -v npx &>/dev/null; then
    echo ""
    echo "WARNING: Node.js is not installed. ccusage needs npx."
    echo "Install from: https://nodejs.org/"
    echo "Or: brew install node (macOS) / sudo apt install nodejs npm (Linux)"
fi

# 8. Install cron job (every 6 hours)
CRON_CMD="0 */6 * * * $CONFIG_DIR/upload.sh >> $CONFIG_DIR/upload.log 2>&1"
(crontab -l 2>/dev/null | grep -v "claude-usage/upload.sh"; echo "$CRON_CMD") | crontab -
echo "Cron job installed (every 6 hours)."

# 9. Run first upload
echo ""
echo "Running first upload..."
bash "$CONFIG_DIR/upload.sh" && echo "" || true

echo ""
echo "========================================"
echo "  Setup complete!"
echo "  Dashboard: https://vale-phd.github.io/claude-usage/"
echo "  Logs: $CONFIG_DIR/upload.log"
echo "========================================"
```

**Step 2: Create setup.ps1**

```powershell
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
```

**Step 3: Commit**

```bash
git add setup.sh setup.ps1
git commit -m "feat: add cross-platform onboarding scripts"
```

---

## Task 4: Build the GitHub Action for Archiving

This action runs whenever someone pushes to `data/`, and merges the daily entries into `history/{username}/YYYY-MM.json` so data persists forever.

**Files:**
- Create: `.github/workflows/archive.yml`

**Step 1: Create the workflow**

```yaml
name: Archive Usage Data

on:
  push:
    paths:
      - 'data/*.json'

permissions:
  contents: write

jobs:
  archive:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Archive data to history
        run: |
          for datafile in data/*.json; do
            [ -f "$datafile" ] || continue

            username=$(basename "$datafile" .json)
            mkdir -p "history/$username"

            # Read daily entries from the uploaded file
            # Each entry has a "date" field like "2026-03-02"
            # We group by YYYY-MM and merge into monthly files

            python3 - "$datafile" "$username" <<'PYEOF'
          import json, sys, os
          from collections import defaultdict

          datafile = sys.argv[1]
          username = sys.argv[2]

          with open(datafile) as f:
              data = json.load(f)

          daily = data.get("daily", [])

          # Group by month
          months = defaultdict(list)
          for entry in daily:
              month = entry["date"][:7]  # "2026-03"
              months[month].append(entry)

          # Merge into existing history files
          for month, entries in months.items():
              history_file = f"history/{username}/{month}.json"

              existing = []
              if os.path.exists(history_file):
                  with open(history_file) as f:
                      existing = json.load(f)

              # Merge: use date as key, new data overwrites old
              by_date = {e["date"]: e for e in existing}
              for e in entries:
                  by_date[e["date"]] = e

              merged = sorted(by_date.values(), key=lambda x: x["date"])

              with open(history_file, "w") as f:
                  json.dump(merged, f, indent=2)

              print(f"  Archived {len(entries)} entries to {history_file}")
          PYEOF
          done

      - name: Commit archived data
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add history/
          git diff --staged --quiet || git commit -m "archive: update history $(date '+%Y-%m-%d')"
          git push
```

**Step 2: Commit**

```bash
git add .github/workflows/archive.yml
git commit -m "feat: add GitHub Action to archive usage data into monthly history"
```

---

## Task 5: Build the Dashboard — HTML/CSS/JS

Single-page app that reads JSON from the repo and renders the UI.

**Files:**
- Create: `index.html`

**Step 1: Create index.html**

This is a complete single-file dashboard with:
- Main view: table of all users with name, total tokens, cost, last active
- Detail view: clicking a name shows daily chart with dropdown filters
- Reads from `data/` for recent data and `history/` for archived data
- Chart.js for visualizations
- Responsive CSS, no build step

The HTML file should contain:

**HTML structure:**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Code Usage — Team Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3"></script>
</head>
```

**CSS (embedded):**
- Clean, minimal design with a dark header
- Table with hover states
- Card layout for user detail view
- Responsive down to mobile

**JavaScript logic:**
1. On load: fetch list of files in `data/` via GitHub API (public repo, no auth needed)
2. For each user JSON, parse daily entries and compute totals
3. Render main table sorted by total cost descending
4. On click: fetch `history/{username}/` files, merge with current data, render chart
5. Dropdown filter: last 4 weeks (default), last 3 months, last 6 months, all time
6. Bar chart: x-axis = dates, y-axis = tokens, color-coded by model
7. Summary cards: total tokens, total cost, most-used model, active days

**Key implementation details:**
- Uses GitHub Contents API to list files: `GET /repos/vale-phd/claude-usage/contents/data`
- Decodes base64 content from API response (avoids CORS issues with raw files on Pages)
- Caches fetched data in sessionStorage to avoid repeated API calls
- Formats tokens as "1.2M" or "340k", costs as "$12.34"
- Chart uses time scale on x-axis with day units

**Step 2: Commit**

```bash
git add index.html
git commit -m "feat: add team usage dashboard"
```

---

## Task 6: Create GitHub Repo and Enable Pages

**Step 1: Install gh CLI (if needed)**

```bash
brew install gh
gh auth login
```

**Step 2: Create remote repo and push**

```bash
cd /Users/vromanov/Documents/Imperial/Projects/Submitted/LLMs+PromptEngineering-2025/Figures/Figure8/claude-usage
gh repo create vale-phd/claude-usage --public --source=. --push
```

**Step 3: Enable GitHub Pages**

```bash
gh api repos/vale-phd/claude-usage/pages -X POST \
    -f build_type=legacy \
    -f source='{"branch":"main","path":"/"}'
```

**Step 4: Verify Pages is live**

Visit: https://vale-phd.github.io/claude-usage/

---

## Task 7: Test the Full Flow

**Step 1: Run the setup script on your own machine**

```bash
bash setup.sh
```

- Enter display name: `vale`
- Enter GitHub token
- Verify the cron job was created: `crontab -l | grep claude-usage`
- Check that `data/vale.json` appeared in the repo

**Step 2: Verify the dashboard**

- Visit https://vale-phd.github.io/claude-usage/
- Confirm your name appears in the table
- Click your name, verify the chart loads
- Test the dropdown filters

**Step 3: Verify the archive action**

- Go to https://github.com/vale-phd/claude-usage/actions
- Confirm the archive workflow ran
- Check that `history/vale/YYYY-MM.json` files were created

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Repo structure | README.md, dirs |
| 2 | Upload scripts | upload.sh, upload.ps1 |
| 3 | Onboarding scripts | setup.sh, setup.ps1 |
| 4 | Archive action | .github/workflows/archive.yml |
| 5 | Dashboard | index.html |
| 6 | Deploy | Create repo, enable Pages |
| 7 | Test | End-to-end verification |
