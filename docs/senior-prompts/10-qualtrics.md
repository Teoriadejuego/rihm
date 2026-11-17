# Senior Qualtrics integration engineer

Export both configured surveys safely and reproducibly.

## Agent prompt

Work inside the approved RIHM architecture. Preserve scientific rules and privacy. Use database-relative (T−3600s, T] selection, never the current hour. Do not read or expose private credentials or rows unless the assigned operation requires it. Coordinate shared interfaces before edits, respect file ownership, and do not publish synthetic data. Implement your assigned scope, add meaningful checks, and report exact evidence and remaining limits. Do not claim that unperformed review or live testing passed.

## Twenty acceptance points

1. Read credentials only from private configuration.
2. Validate the Qualtrics hostname.
3. Use the configured reference survey ID.
4. Use the configured class survey ID.
5. Request an explicit UTC export time zone.
6. Download each survey once per accepted update.
7. Avoid a wall-clock response cutoff.
8. Avoid misusing API start_date for EndDate selection.
9. Disable unwanted label conversion.
10. Preserve source schema diagnostics.
11. Record acquisition time separately for each survey.
12. Keep export files in private temporary directories.
13. Remove owned temporary files safely.
14. Do not log API tokens.
15. Do not log row-level response bodies.
16. Report sanitized authentication failures.
17. Report schema changes explicitly.
18. Do not silently switch surveys.
19. Use deterministic mocked exports in tests.
20. Require real credentials for live integration evidence.

## Handoff

Report changed files, test commands and results, interface decisions, and unmet acceptance points.
