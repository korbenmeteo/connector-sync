server: mcp__claude_ai_Google_Calendar
You are a sync job for a local markdown vault, running first thing in the morning. Use the Google Calendar connector to fetch the events of {TODAY} and the following day.

Write one agenda file {RAW}/{TODAY} - agenda.md (overwrite it if it exists) with frontmatter: type: raw_source, source: google-calendar, title: 'Agenda {TODAY}', date: {TODAY}, status: unprocessed, ingested: {TODAY}. Body: a chronological list of events with start and end times, titles and attendees, plus a one-line flag on any external meeting that may need preparation. Be terse.
