#!/usr/bin/env bash
# Runs connector-sync.sh against a fake claude CLI in a temporary vault and checks each guarantee.
# One assertion per line: under set -e, a failure inside `a && b` or `! cmd` does not stop the script.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SYNC="$HERE/../skills/connector-sync/scripts/connector-sync.sh"
V="$(mktemp -d)"
mkdir -p "$V/sources"
printf 'server: mcp__claude_ai_Demo\nFetch items from {SINCE} to {TODAY} into {RAW}/.\n' > "$V/sources/demo.md"
printf 'VAULT="%s"\nSOURCES_DIR="%s/sources"\nMAX_DAYS=30\n' "$V" "$V" > "$V/test.env"
export CONNECTOR_SYNC_CONFIG="$V/test.env" CLAUDE_BIN="$HERE/fake-claude.sh" FAKE_LOG="$V/fake"
S="$V/.connector-sync"
days_ago() { date -v-"$1"d +%F 2>/dev/null || date -d "-$1 days" +%F; }
field() { sed -n "s/^$1: //p" "$S/demo.health.md"; }
ok() { echo "ok - $1"; }
fails() { if "$@"; then echo "not ok - expected a failure: $*"; exit 1; fi; }

FAKE_MODE=ok bash "$SYNC" demo
test "$(field status)" = healthy
test "$(field items)" = 1
test "$(cat "$S/demo.last-ok")" = "$(date +%F)"
grep -q "from $(days_ago 2) to $(date +%F) into raw/demo/" "$FAKE_LOG.prompt"
ok "first run writes one item, looks back 2 days, fills the placeholders"

grep -q "mcp__claude_ai_Demo" "$FAKE_LOG.tools"
grep -q "Edit(raw/demo/\*\*)" "$FAKE_LOG.tools"
fails grep -qiE "bypass|dangerously" "$FAKE_LOG.tools"
ok "permissions: the connector, read tools, writes to raw/demo/ only"

FAKE_MODE=ok bash "$SYNC" demo
test "$(field items)" = 0
test "$(ls "$V/raw/demo" | wc -l)" -eq 1
ok "second run adds nothing"

days_ago 9 > "$S/demo.last-ok"
fails env FAKE_MODE=refused bash "$SYNC" demo
test "$(field status)" = error
grep -q "API unreachable" "$S/demo.health.md"
test "$(cat "$S/demo.last-ok")" = "$(days_ago 9)"
ok "unreachable API: exit 1, plain cause, last success kept"

fails env FAKE_MODE=expired bash "$SYNC" demo
grep -q "claude auth login" "$S/demo.health.md"
ok "expired login: says which command fixes it"

fails env FAKE_MODE=error bash "$SYNC" demo
grep -q "source returned an error" "$S/demo.health.md"
ok "source error (quota): reported as an error, not as zero items"

FAKE_MODE=ok bash "$SYNC" demo
grep -q "from $(days_ago 9) " "$FAKE_LOG.prompt"
ok "next good run catches up from the last success"

days_ago 45 > "$S/demo.last-ok"
FAKE_MODE=ok bash "$SYNC" demo
grep -q "from $(days_ago 30) " "$FAKE_LOG.prompt"
ok "catch-up is capped at MAX_DAYS"

test "$(wc -l < "$S/demo.jsonl")" -eq 7
ok "one JSON line per run"
echo "all checks passed (vault left in $V)"
