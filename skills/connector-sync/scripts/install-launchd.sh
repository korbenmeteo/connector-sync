#!/usr/bin/env bash
# install-launchd.sh <source>...: schedule one daily run per source on macOS, 5 minutes apart.
# Staggering matters: Gmail and Google Calendar share a Google quota and fail when they start together.
#   HOUR=6 bash install-launchd.sh granola gmail google-calendar
#   bash install-launchd.sh --uninstall granola gmail google-calendar
#   DRY_RUN=1 bash install-launchd.sh granola    # print the plist, change nothing
set -euo pipefail

UNINSTALL=0
[ "${1:-}" = "--uninstall" ] && { UNINSTALL=1; shift; }
[ $# -gt 0 ] || { echo "usage: install-launchd.sh [--uninstall] <source>..." >&2; exit 2; }

SCRIPT="$(cd "$(dirname "$0")" && pwd)/connector-sync.sh"
CONFIG="${CONNECTOR_SYNC_CONFIG:-$HOME/.config/connector-sync.env}"
DEST="$HOME/Library/LaunchAgents"
HOUR="${HOUR:-6}"
minute=0

for src in "$@"; do
  label="io.github.connector-sync.$src"
  plist="$DEST/$label.plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  if [ "$UNINSTALL" = 1 ]; then rm -f "$plist"; echo "removed: $label"; continue; fi
  body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCRIPT</string><string>$src</string></array>
  <key>EnvironmentVariables</key><dict><key>CONNECTOR_SYNC_CONFIG</key><string>$CONFIG</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$minute</integer></dict>
  <key>RunAtLoad</key><false/>
</dict></plist>"
  if [ -n "${DRY_RUN:-}" ]; then echo "$body"; else
    mkdir -p "$DEST"; echo "$body" > "$plist"
    launchctl bootstrap "gui/$(id -u)" "$plist"
    printf 'scheduled: %s at %02d:%02d\n' "$label" "$HOUR" "$minute"
  fi
  minute=$((minute + 5))
done
[ -n "${DRY_RUN:-}" ] || [ "$UNINSTALL" = 1 ] || echo "Test one now: launchctl kickstart -k gui/$(id -u)/io.github.connector-sync.$1"
