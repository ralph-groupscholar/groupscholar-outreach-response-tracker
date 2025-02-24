# Group Scholar Outreach Response Tracker

CLI for capturing outreach attempts and monitoring response rates across channels. Built for ops teams that need fast visibility into which touchpoints are working and where follow-ups are stalled.

## Features
- Initialize and seed the production outreach response schema
- Import outreach logs from CSV exports
- Log one-off outreach attempts from the terminal
- Generate response rate and response-time reports by channel
- Surface outstanding follow-ups that need outreach nudges

## Usage

Set a database connection string before running commands:

```bash
export GS_DB_URL="postgres://USER:PASSWORD@HOST:PORT/DB"
```

Initialize tables and seed data:

```bash
zig build run -- init
zig build run -- seed
```

Import from CSV (requires headers: scholar_id, channel, sent_at, responded_at, response_type, notes):

```bash
zig build run -- import data/outreach.csv
```

Log a single outreach attempt:

```bash
zig build run -- log --scholar sch-1122 --channel email --sent "2025-11-15 14:00:00+00" --response-type schedule --notes "Booked a follow-up call."
```

Run reports:

```bash
zig build run -- report
```

View the follow-up queue (defaults to 48 hours outstanding, limit 25):

```bash
zig build run -- queue --hours 72 --limit 10 --channel sms
```

Triage scholars with repeated unanswered outreach (defaults to 30 days, min 2 attempts):

```bash
zig build run -- triage --days 14 --min-attempts 3 --limit 15
```

## Development

Run tests:

```bash
zig build test
```

## Tech
- Zig
- PostgreSQL (psql CLI)

## Notes
- The CLI reads the `GS_DB_URL` environment variable and delegates SQL execution to `psql`.
- Use UTC timestamps for consistent reporting.
