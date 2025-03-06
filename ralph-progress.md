# Ralph Progress Log

## 2026-02-08
- Initialized the Zig CLI scaffold with outreach logging commands and CSV import.
- Added PostgreSQL schema + seed data scripts for outreach response tracking.
- Documented usage, environment setup, and reporting flow in README.

## 2026-02-08
- Added a follow-up queue command with an hours threshold to flag overdue outreach attempts.
- Documented the new queue workflow in the README and added parsing tests for positive integers.

## 2026-02-08
- Extended the follow-up queue command with channel filtering and result limits for targeted outreach lists.
- Updated README examples to reflect the new queue options.

## 2026-02-08
- Added an SLA coverage report with optional channel and recent-window filters.
- Documented the SLA report workflow in the README.

## 2026-02-08
- Added a triage command to surface scholars with repeated unanswered outreach attempts in a recent window.
- Expanded CLI usage + README with triage workflow and added a parsing test for negative inputs.

## 2026-02-08
- Added a focus command to surface scholars with low response rates over a recent window, with filters for channel, minimum sends, and limit.
- Documented the focus workflow in the README.
