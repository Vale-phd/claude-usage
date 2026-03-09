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
    PAYLOAD=$(cat <<HEREDOC
{
  "message": "usage: update ${DISPLAY_NAME} $(date '+%Y-%m-%d %H:%M')",
  "content": "$CONTENT",
  "sha": "$SHA"
}
HEREDOC
)
else
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
