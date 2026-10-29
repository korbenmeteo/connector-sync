---
name: connector-sync
description: Schedule unattended syncs of claude.ai connectors (Granola, Gmail, Google Calendar or any other) into markdown files, with automatic catch-up after failures, least-privilege permissions and plain-language health checks. Use when the user wants their meetings, email or calendar copied into a notes vault every day, wants to add a new source, or asks why a scheduled sync stopped working.
---

# Connector sync

Copies what your claude.ai connectors see into a markdown vault on a schedule, by running
`claude -p` headless once per source. The scripts handle what a prompt cannot: the date
window, permissions, and telling you clearly when and why a run failed.

## How it works

- `scripts/connector-sync.sh <source>` runs one source. It reads `sources/<source>.md`, whose first line names the connector (`server: mcp__claude_ai_Granola`) and whose body is the prompt.
- The window starts at the last successful run, so a gap fills itself on the next good run (capped at `MAX_DAYS`, 30 by default).
- Claude may use the connector, read tools, and write to `raw/<source>/` only. No bypass mode.
- Each run writes `.connector-sync/<source>.health.md`, one JSON line, and on failure a macOS notification with the cause.

## Set up

1. Check the user is logged in with their claude.ai account (`claude auth status` shows `"authMethod": "claude.ai"`) and that the connectors are enabled on claude.ai. A token from `claude setup-token` will not do: it cannot load claude.ai connectors.
2. Copy `connector-sync.example.env` to `~/.config/connector-sync.env` and set `VAULT`.
3. For each source, find the connector name with `claude mcp list` (`claude.ai Google Calendar` becomes `mcp__claude_ai_Google_Calendar`: spaces and dots turn into `_`). Start from the files in `sources/`; copy them to `SOURCES_DIR` if the user wants to edit them.
4. Run one source by hand from a normal terminal: `bash scripts/connector-sync.sh granola`. Read the health file.
5. Schedule: `bash scripts/install-launchd.sh granola gmail google-calendar` (macOS, 06:00 then 5 minutes apart). On Linux, one cron line per source, also staggered.
6. Test the real scheduled environment, not the terminal: `launchctl kickstart -k gui/$(id -u)/io.github.connector-sync.granola`.

## Writing a source prompt

- Use `{SINCE}`, `{TODAY}` and `{RAW}`; the script fills them in.
- Make it idempotent: name the stable id (meeting id, thread id) to store in the frontmatter and tell Claude to Grep `{RAW}/` for it before writing.
- Keep it read only on the source side; the script adds that rule anyway.
- The script appends the contract: finish with `ITEMS: <n>`, or `ITEMS: ERROR` if the source failed. A run without that line counts as a failure.

## When a sync fails

Read `.connector-sync/<source>.health.md`, then the end of `<source>.log`.

| Cause in the health file | What to do |
|---|---|
| `login expired` | The user runs `claude auth login` in a terminal (it opens a browser). Then kickstart the job. |
| `API unreachable` | Look for `ANTHROPIC_BASE_URL` in `~/.claude/settings.json` and in the environment. A leftover proxy address breaks every scheduled run while the desktop app keeps working, because the app sets its own. |
| `source returned an error` | Usually a quota. Check the jobs are staggered; the next run catches up. |
| `no ITEMS line` | The connector did not load or the run stopped early. Check `claude mcp list` from a terminal. |

After a fix, the next good run catches up on its own. For a gap longer than `MAX_DAYS`, write
the start date into `.connector-sync/<source>.last-ok` before running.
