#!/usr/bin/env bash
# connector-sync.sh <source>: run one claude.ai connector headless and land its items as markdown.
#
# The prompt for each source lives in sources/<source>.md. Its first line names the connector
# (`server: mcp__claude_ai_Granola`); {SINCE}, {TODAY} and {RAW} in the rest are filled in here.
#
# What this script guarantees, whatever the model does:
#   - catch-up: the window starts at the last successful run (capped at MAX_DAYS), not a fixed delay;
#   - least privilege: the source's connector, read tools, and writes to RAW_DIR/<source>/ only;
#   - loud failures: health file, JSON line and (on macOS) a notification, with a plain cause.
#
# Config: $CONNECTOR_SYNC_CONFIG, else ~/.config/connector-sync.env (see connector-sync.example.env).

set -uo pipefail

SRC="${1:?usage: connector-sync.sh <source>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONNECTOR_SYNC_CONFIG:-$HOME/.config/connector-sync.env}"
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"
: "${VAULT:?set VAULT in $CONFIG}"
RAW_DIR="${RAW_DIR:-raw}"
STATE_DIR="${STATE_DIR:-.connector-sync}"
SOURCES_DIR="${SOURCES_DIR:-$HERE/sources}"
DEFAULT_DAYS="${DEFAULT_DAYS:-2}"
MAX_DAYS="${MAX_DAYS:-30}"

PROMPT_FILE="$SOURCES_DIR/$SRC.md"
[ -f "$PROMPT_FILE" ] || { echo "no prompt file: $PROMPT_FILE" >&2; exit 2; }
SERVER="$(sed -n '1s/^server: *//p' "$PROMPT_FILE")"
[ -n "$SERVER" ] || { echo "first line of $PROMPT_FILE must be 'server: mcp__claude_ai_<Name>'" >&2; exit 2; }

cd "$VAULT" || exit 1
mkdir -p "$STATE_DIR" "$RAW_DIR/$SRC"
LOG="$STATE_DIR/$SRC.log"
JSONL="$STATE_DIR/$SRC.jsonl"
HEALTH="$STATE_DIR/$SRC.health.md"
STATE="$STATE_DIR/$SRC.last-ok"

days_ago() { date -v-"$1"d +%F 2>/dev/null || date -d "-$1 days" +%F; }  # BSD, then GNU date
TODAY="$(date +%F)"
SINCE="$(cat "$STATE" 2>/dev/null || days_ago "$DEFAULT_DAYS")"
FLOOR="$(days_ago "$MAX_DAYS")"
[[ "$SINCE" < "$FLOOR" ]] && SINCE="$FLOOR"

PROMPT="$(sed 1d "$PROMPT_FILE")"
PROMPT="${PROMPT//\{SINCE\}/$SINCE}"
PROMPT="${PROMPT//\{TODAY\}/$TODAY}"
PROMPT="${PROMPT//\{RAW\}/$RAW_DIR/$SRC}"
PROMPT="$PROMPT

Rules for every source: write files only under $RAW_DIR/$SRC/ and nowhere else. The source is read only: never send, reply, create, modify, archive or delete anything in it. If the source tools are not available or return an error, say why and print ITEMS: ERROR. Otherwise finish with one line exactly: ITEMS: <number of files written or overwritten>"

unset CLAUDECODE 2>/dev/null || true  # allows a manual test from inside a Claude session
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"  # launchd starts with a minimal PATH
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"

RUN_OUT="$(mktemp)"
echo "[$(date '+%Y-%m-%d %H:%M')] $SRC start (since $SINCE)" >> "$LOG"
if [ -z "$CLAUDE_BIN" ]; then
  echo "claude CLI not found on PATH" > "$RUN_OUT"; EXIT=127
else
  "$CLAUDE_BIN" -p "$PROMPT" \
    --allowedTools "$SERVER" "Read" "Glob" "Grep" "Edit($RAW_DIR/$SRC/**)" \
    < /dev/null > "$RUN_OUT" 2>&1
  EXIT=$?
fi
cat "$RUN_OUT" >> "$LOG"

ITEMS="$(grep -oE '^ITEMS: ([0-9]+|ERROR)' "$RUN_OUT" | tail -1 | cut -d' ' -f2)"
FAIL=""
[ "$EXIT" -ne 0 ] && FAIL="claude exit $EXIT"
grep -qiE "Failed to authenticate|OAuth session expired|Invalid authentication|not authenticated|Please run /login" "$RUN_OUT" \
  && FAIL="${FAIL:+$FAIL; }login expired: run 'claude auth login' in a terminal"
grep -qiE "ECONNREFUSED|Connection refused|ENOTFOUND|ETIMEDOUT" "$RUN_OUT" \
  && FAIL="${FAIL:+$FAIL; }API unreachable: check ANTHROPIC_BASE_URL in ~/.claude/settings.json and your network"
if [ -z "$FAIL" ] && [ "$ITEMS" = ERROR ]; then
  FAIL="the source returned an error (quota, connector down): see $LOG"
elif [ -z "$FAIL" ] && ! [[ "$ITEMS" =~ ^[0-9]+$ ]]; then
  FAIL="no ITEMS line: connector missing or run incomplete, see $LOG"
fi
rm -f "$RUN_OUT"

NOW="$(date '+%Y-%m-%dT%H:%M:%S%z')"
if [ -z "$FAIL" ]; then
  echo "$TODAY" > "$STATE"
  STATUS=healthy
else
  STATUS=error; ITEMS=0
  command -v osascript >/dev/null && osascript -e "display notification \"$FAIL\" with title \"connector-sync: $SRC failed\"" 2>/dev/null
fi

cat > "$HEALTH" <<EOF
---
source: $SRC
status: $STATUS
last_success: $(cat "$STATE" 2>/dev/null || echo never)
last_attempt: $NOW
window_since: $SINCE
items: $ITEMS
error: "$FAIL"
---
EOF
printf '{"ts":"%s","source":"%s","items":%s,"status":"%s","since":"%s","error":"%s"}\n' \
  "$NOW" "$SRC" "$ITEMS" "$STATUS" "$SINCE" "$FAIL" >> "$JSONL"
echo "[$(date '+%Y-%m-%d %H:%M')] $SRC $STATUS items=$ITEMS ${FAIL:+($FAIL)}" >> "$LOG"
[ "$STATUS" = healthy ]
