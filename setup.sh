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
echo "You need a GitHub Fine-Grained Personal Access Token."
echo "Create one at: https://github.com/settings/personal-access-tokens/new"
echo ""
echo "  Token name:          claude-usage"
echo "  Expiration:          1 year"
echo "  Repository access:   Only select repositories → vale-phd/claude-usage"
echo "  Permissions:         Contents → Read and write"
echo "  (leave everything else as No access)"
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
    echo "Check that your token has Contents read/write for vale-phd/claude-usage."
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
curl -sfL "https://raw.githubusercontent.com/Vale-phd/claude-usage/master/upload.sh" \
    -o "$CONFIG_DIR/upload.sh"
if [ ! -s "$CONFIG_DIR/upload.sh" ] || head -1 "$CONFIG_DIR/upload.sh" | grep -qv '^#!/bin/bash'; then
    echo "ERROR: Failed to download upload script."
    exit 1
fi
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
