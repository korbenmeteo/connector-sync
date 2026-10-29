# connector-sync

Copy what your claude.ai connectors see (Granola meetings, Gmail threads, Google Calendar,
or anything else you have connected) into a markdown vault every morning, without babysitting it.

My notes vault pulls meetings, email and calendar through Claude Code in headless mode. Over
five months the job broke three times: 13 days in June, 24 days across August and September,
then a week in October. Every time, it looked fine. The October one was a single line in a
settings file, pointing Claude Code at a local proxy that was no longer running. The desktop app
ignored it; the scheduled job hit a closed port every morning.

This is the version I rebuilt after that. When the fix landed, one run per source caught up on
its own: 18 meetings and 20 email threads.

## What it does

1. **One script, one prompt per source.** `sources/granola.md` says which connector to use and what to write. Adding a source is adding a file.
2. **Catch-up instead of a fixed window.** Each run starts from the last success, so a gap fills itself on the next good run (capped at 30 days).
3. **Least privilege.** Claude gets the source's connector, read tools, and write access to `raw/<source>/` only. No bypass mode.
4. **Failures that say why.** A health file, a JSON line and a macOS notification, in plain words: login expired, API unreachable, source error (quota), connector missing.
5. **Idempotent.** Prompts store the source's own id and check for it before writing, so reruns add nothing.
6. **Staggered scheduling.** The launchd installer spaces sources 5 minutes apart; Gmail and Google Calendar share a quota and fail when they start together.

## Requirements

- Claude Code CLI, logged in with your claude.ai account (`claude auth status`).
- The connectors you want, enabled on claude.ai.
- bash. macOS for the launchd installer and notifications; cron works on Linux.

## Install

As a Claude Code plugin:

```
/plugin marketplace add korbenmeteo/connector-sync
/plugin install connector-sync@connector-sync
```

Or clone the repository and use the scripts directly.

## Quick start

```bash
cp skills/connector-sync/connector-sync.example.env ~/.config/connector-sync.env   # set VAULT
bash skills/connector-sync/scripts/connector-sync.sh granola                       # one run by hand
cat "$VAULT/.connector-sync/granola.health.md"
bash skills/connector-sync/scripts/install-launchd.sh granola gmail google-calendar
```

Or ask Claude: *"Set up a daily sync of my Granola meetings into my vault."*

To see every guarantee checked against a fake CLI: `bash examples/run-example.sh`.

## What I learned

- **A long-lived token is not the answer.** `claude setup-token` gives a token that can call the model but cannot load claude.ai connectors. Scheduled connector runs need your normal claude.ai login, and when that expires you have to run `claude auth login` yourself. The script tells you when.
- **Test under the scheduler, not in your terminal.** The desktop app and your shell set their own environment. `launchctl kickstart` runs the job exactly as it runs at 6am.
- **Silence is not success.** A run that never prints its item count is a failure, even with exit code 0.

## Privacy

Everything runs on your machine with your own Claude login. Files land in your vault and
nowhere else. Your config, health files and synced items are listed in `.gitignore`.

## Limits

- Each run uses your Claude plan. Three sources a day is a few short sessions.
- Claude writes the files; the prompt is the contract. Read the prompts before you trust them.
- Connector names and tools change on the provider side. If a source starts failing with `no ITEMS line`, check `claude mcp list`.

## Author

Built by Ruben Hallali ([@RubenHallali](https://x.com/RubenHallali)). I am building my own
tooling in public; issues and pull requests are welcome.

## Licence

MIT
