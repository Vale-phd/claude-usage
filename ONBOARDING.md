# Claude Code Usage Dashboard — Onboarding

## Step 1: Create a GitHub Fine-Grained Token

1. Go to https://github.com/settings/personal-access-tokens/new
2. **Token name:** `claude-usage`
3. **Expiration:** 1 year (or custom)
4. **Resource owner:** your personal account
5. **Repository access:** select **Only select repositories** → choose `vale-phd/claude-usage`
6. **Permissions → Repository permissions:**
   - **Contents:** Read and write
   - Leave everything else as No access
7. Click **Generate token** and copy it

## Step 2: Run the setup script

**macOS / Linux:**

```bash
bash <(curl -sL https://vale-phd.github.io/claude-usage/setup.sh)
```

**Windows (PowerShell as Admin):**

```powershell
irm https://vale-phd.github.io/claude-usage/setup.ps1 | iex
```

It will ask for:
- Your **display name** (e.g. `john`) — this is how you appear on the dashboard
- Your **GitHub token** from Step 1

## Step 3: Done

Your usage data uploads automatically every 6 hours in the background. No action needed.

**Dashboard:** https://vale-phd.github.io/claude-usage/

## Requirements

- **Node.js** must be installed (`node --version` to check)
  - macOS: `brew install node`
  - Linux: `sudo apt install nodejs npm`
  - Windows: https://nodejs.org/

## Troubleshooting

- **Check logs:** `~/.config/claude-usage/upload.log`
- **Manual upload:** `~/.config/claude-usage/upload.sh` (macOS/Linux)
- **Verify cron:** `crontab -l | grep claude-usage` (macOS/Linux)
