# RIHM reconstruction plan

Status: approved for implementation. Product language: English. Existing destinations remain
[researcher](https://teoria-juegos.shinyapps.io/rihm-profesor/) and
[students](https://teoriadejuego.github.io/rihm/).

## Purpose and boundaries

The researcher explains the experiment, presents twelve teaching slides, and manually
updates the latest published dataset. Students learn, explore and compare the most
recent privacy-protected snapshot. They never connect to Qualtrics or Shiny.

The researcher runs Shiny with bslib on the existing shinyapps.io account. Students run
modular JavaScript, HTML and CSS built with Vite and served by GitHub Pages. No new
database service or paid hosting is required. Raw survey rows remain private and
ephemeral on the researcher server; GitHub stores aggregates and static source only.

## Definition of the latest group

1. Export the complete class survey with an explicit UTC export time zone.
2. Normalize and deduplicate records, then find the maximum valid **EndDate**, T.
3. Select records whose EndDate is in **(T − 3600 seconds, T]**.
4. Determine this interval before excluding incomplete or non-binary responses.
5. Apply the existing scientific classification and privacy rules to that group.

This is a database-relative hour, never the hour before the current clock time. An old
database still has a latest group. Boundary ties are retained; the lower boundary is
excluded. Missing EndDate is not replaced with RecordedDate. If the selected group
has no usable responses, report that fact rather than silently moving to an older
group. The international reference uses all valid mapped reference responses.
Session codes no longer select the group. Acquisition time, response interval and
publication time are distinct labels.

## Researcher experience

Five sections: Project, Teach, Latest group, Update and Diagnostics. Teach provides
twelve slides, presenter notes, keyboard controls and full-screen presentation. A
presentation pins its snapshot so results do not change midway through explanation.
Latest group restores the last public snapshot after login or restart.

“Update and publish” downloads both configured surveys once, validates, classifies,
aggregates, suppresses and publishes automatically. There is no extra review checkbox.
One process-global coordinator enforces one job at a time and at least 180 seconds
between accepted updates, including requests from other tabs. Unknown restart state
starts with a conservative 180-second wait. The deployed application must have one
worker; a multi-worker deployment needs a shared external coordinator.

Expensive work runs outside the interactive Shiny loop. Server-side authorization is
checked before starting work and before publication writes. Logout revokes permission
for uncommitted work; an already accepted write is reconciled. Failures retain the last
valid publication. An unchanged semantic aggregate does not create another publication.
Demonstration is clearly labelled and isolated from automatic publication.

## Student experience

Learn explains the allocation task. Explore shows overlapping behaviour indicators,
inconsistency with its separate denominator, and a 4×4 compassion/envy matrix. Compare
shows class versus reference and differences in percentage points. Methods explains
classification, denominators, suppression, group timing and interpretive limits.

Charts have text values and equivalent tables; filters are keyboard accessible. Small
screens retain content and readable labels. Colour is not the sole carrier of meaning.
Empty, suppressed, offline and failed-refresh states explain the next useful action.

On load, every 60 seconds while visible, and after returning to a hidden tab, the page
checks the manifest. It fetches results only when the publication changes, validates
schema/publication/hash, then replaces the view atomically. Compatible filters survive.
A failed refresh preserves the last valid view and reports its stale status.

## Data contract and privacy

Schema 2.0.0 preserves aggregate behaviour and matrix cells. Metadata adds
`window_start_utc`, `window_end_utc`, `selection_rule = latest_response_hour`,
`class_source_at_utc`, `reference_source_at_utc`, `classification_version`,
`privacy_version` and `content_fingerprint`. The fingerprint includes semantic public
content and rules, excluding publication identifiers and acquisition/generated times.
The manifest includes `results_sha256`, computed from the exact UTF-8 JSON bytes.

The reader supports legacy 1.0.0, including `not-published`, without inventing an interval.
Publication uses strict allowed fields and coherent matching files in one Git commit.
The publisher rejects unexpected rows, identifiers, private values and malformed cells.

Preserve the original Selfish, Spiteful, Egalitarian, dp_efficiency, Altruist, Ineqseek,
Antisocial and Inconsistent rules. Four displayed social indicators overlap and use
consistent responses; inconsistency uses complete binary responses. dp_efficiency is
tested but not separately plotted because its current rule equals Altruist.

Suppress any count, denominator or complementary count below five. Preserve secondary
and cross-table safeguards. Suppressed numeric values are null. This is protection of
each snapshot, **not a guarantee of anonymity against comparisons between versions**.
Git history retains older public aggregates. The agreed three-minute update interval
does not add a one-hour overlapping-window prohibition.

## Delivery sequence

1. Preserve the current source and production snapshots; work on `codex/rebuild-v2`.
2. Implement and test temporal selection, v2 contract and idempotent publication.
3. Build the student reader and accessible visualisations against deterministic fixtures.
4. Build the authenticated researcher panel, asynchronous coordinator and slide deck.
5. Integrate build, privacy scan, dependency locks, deployment guard and operations docs.
6. Run R, JS and browser checks; inspect desktop/mobile screenshots; test 30/60/200 clients.
7. Validate private Qualtrics access when credentials exist, then deploy verified code to
   the existing hosting. Never replace real published data with an invented dataset.
8. Verify both deployed destinations and record evidence and remaining limits.

## Specialist assignments

Twenty role prompts, each containing exactly twenty review/build points, live in
`docs/senior-prompts/`. They are work specifications, not twenty fictitious people or
claims of twenty independent reviews. The three delegated implementation streams cover
data/publication, researcher/coordinator and student frontend. The coordinating agent
integrates deployment, documentation, test evidence and cross-component review.

Acceptance evidence and unfinished checks belong in `docs/implementation-status.md`.
