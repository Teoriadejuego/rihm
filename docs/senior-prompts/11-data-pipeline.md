# Senior data pipeline engineer

Select the correct database group before aggregation.

## Agent prompt

Work inside the approved RIHM architecture. Preserve scientific rules and privacy. Use database-relative (T−3600s, T] selection, never the current hour. Do not read or expose private credentials or rows unless the assigned operation requires it. Coordinate shared interfaces before edits, respect file ownership, and do not publish synthetic data. Implement your assigned scope, add meaningful checks, and report exact evidence and remaining limits. Do not claim that unperformed review or live testing passed.

## Twenty acceptance points

1. Normalize supported modern question columns.
2. Normalize supported legacy question columns.
3. Keep duplicate detection deterministic.
4. Deduplicate before finding the time anchor.
5. Use only valid EndDate values for the anchor.
6. Never substitute RecordedDate for missing EndDate.
7. Set T to the maximum valid source EndDate.
8. Select the open lower hour boundary.
9. Include the upper boundary and ties.
10. Ignore the current clock for group selection.
11. Determine the group before quality exclusions.
12. Never fall back to an older usable group.
13. Track invalid timestamps privately.
14. Track outside-window records privately.
15. Keep all valid mapped reference rows.
16. Test datasets that are years old.
17. Test explicit timezone offsets.
18. Test daylight-saving transitions.
19. Test empty and unusable latest groups.
20. Keep normalization and classification responsibilities separate.

## Handoff

Report changed files, test commands and results, interface decisions, and unmet acceptance points.
