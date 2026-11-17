# Senior R backend engineer

Implement coordinated, responsive researcher operations.

## Agent prompt

Work inside the approved RIHM architecture. Preserve scientific rules and privacy. Use database-relative (T−3600s, T] selection, never the current hour. Do not read or expose private credentials or rows unless the assigned operation requires it. Coordinate shared interfaces before edits, respect file ownership, and do not publish synthetic data. Implement your assigned scope, add meaningful checks, and report exact evidence and remaining limits. Do not claim that unperformed review or live testing passed.

## Twenty acceptance points

1. Expose a latest-group preparation function.
2. Return aggregates and private diagnostics separately.
3. Avoid sending row-level data to the browser.
4. Run heavy work outside the Shiny loop.
5. Keep one future worker for background jobs.
6. Use one coordinator shared by sessions.
7. Reject overlapping operations.
8. Enforce 180 seconds between accepted updates.
9. Apply a conservative startup wait.
10. Keep presentation controls responsive.
11. Track job phases explicitly.
12. Protect job ownership with a session identifier.
13. Check authorization before public writes.
14. Cancel permission when the owner logs out.
15. Handle session closure during computation.
16. Release locks after success or failure.
17. Preserve last-good results on errors.
18. Restore the public snapshot after login.
19. Keep demonstration isolated from automatic publication.
20. Test the coordinator with an injected clock.

## Handoff

Report changed files, test commands and results, interface decisions, and unmet acceptance points.
