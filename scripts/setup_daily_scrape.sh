#!/usr/bin/env bash
# One-time setup: makes sync_to_supabase.py run automatically once a day
# via macOS's launchd (the modern replacement for cron) — scraping VOX
# and upserting films/branches/showtimes straight into Supabase.
#
# Before running this for the first time:
#   1. Run schema.sql once in the Supabase SQL Editor.
#   2. Create scripts/.env with SUPABASE_URL and
#      SUPABASE_SERVICE_ROLE_KEY (see the docstring at the top of
#      sync_to_supabase.py for exactly why this must be its own file,
#      separate from the app's root .env).
#
# Then run this yourself from a normal Terminal (not through Claude):
#
#   cd path/to/final_project/scripts
#   chmod +x setup_daily_scrape.sh
#   ./setup_daily_scrape.sh
#
# It only touches your own LaunchAgents folder and installs one pip
# package - nothing else on your machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3)"
LABEL="com.ticked.voxsync"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_PATH="$SCRIPT_DIR/vox_sync.log"

if [ -z "$PYTHON_BIN" ]; then
  echo "Couldn't find python3 on your PATH. Install Python 3 first, then re-run this script." >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "scripts/.env not found." >&2
  echo "Create it first with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY —" >&2
  echo "see the docstring at the top of sync_to_supabase.py." >&2
  exit 1
fi

echo "Using Python: $PYTHON_BIN"
echo "Installing/checking curl_cffi + requests + beautifulsoup4 for that interpreter..."
"$PYTHON_BIN" -m pip install --quiet curl_cffi requests beautifulsoup4

# Default: run once a day at 08:00 local time. Change the Hour value
# below (0-23) and re-run this script if you'd rather it ran at a
# different time.
HOUR=8
MINUTE=0

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PYTHON_BIN}</string>
        <string>${SCRIPT_DIR}/sync_to_supabase.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${HOUR}</integer>
        <key>Minute</key>
        <integer>${MINUTE}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST

# Reload cleanly in case it's already installed from a previous run.
launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo ""
echo "Done. ${LABEL} is scheduled to run daily at $(printf '%02d:%02d' "$HOUR" "$MINUTE")."
echo "Each run scrapes VOX and upserts films/branches/showtimes into Supabase,"
echo "and logs to ${LOG_PATH}."
echo ""
echo "Useful commands:"
echo "  Run it right now (test):  launchctl start ${LABEL}"
echo "  Check it's loaded:        launchctl list | grep ${LABEL}"
echo "  See the last run's log:   cat '${LOG_PATH}'"
echo "  Turn it off later:        launchctl unload '${PLIST_PATH}' && rm '${PLIST_PATH}'"
echo ""
echo "Note: your Mac has to be on (awake or just plugged in/lid open is enough - it"
echo "doesn't need to be unlocked) at ${HOUR}:00 for the job to fire. If it's asleep,"
echo "macOS runs it the next time it wakes up rather than skipping the day."
