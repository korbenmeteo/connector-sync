#!/usr/bin/env bash
# Stands in for the claude CLI so the tests run without an account.
# FAKE_MODE: ok (writes one item, once), refused (API unreachable), expired (login expired), error (source error).
prompt="" ; tools=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    --allowedTools) shift; while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do tools="$tools $1"; shift; done ;;
    *) shift ;;
  esac
done
printf '%s' "$prompt" > "$FAKE_LOG.prompt"
printf '%s' "$tools" > "$FAKE_LOG.tools"
case "${FAKE_MODE:-ok}" in
  refused) echo "API Error: Connection refused (ECONNREFUSED)"; exit 1 ;;
  expired) echo "Failed to authenticate: OAuth session expired and could not be refreshed"; exit 1 ;;
  error)   echo "The connector answered: Resource has been exhausted (check quota)."; echo "ITEMS: ERROR" ;;
  ok)
    out="raw/demo/2026-01-01 - Example meeting.md"
    if grep -rqs "demo_id: 1" raw/demo; then echo "ITEMS: 0"; else
      printf -- '---\nsource: demo\ndemo_id: 1\n---\nExample item.\n' > "$out"; echo "ITEMS: 1"; fi ;;
esac
