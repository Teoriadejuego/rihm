# Optimization results

Date: 2026-11-18 (Europe/Madrid). This pass keeps the original scientific rules,
database-relative response hour, privacy threshold and real published data.

## Student dashboard

Five consecutive manifest checks against the real public snapshot previously caused
ten complete view replacements. The optimized reader causes **zero** complete view
replacements and removes **zero** elements. The same matrix and filter nodes remain
mounted; only status text changes. Both measurements made five manifest requests and
zero additional result downloads. Browser regression checks also preserve disclosure
focus and horizontal table scroll during an unsuccessful refresh and a new publication.

Percentage validation now matches the R producer's decimal rounding. Eighteen frozen
R-generated cases include exact half ties and nearby binary floating-point values.
For example, 5 of 80 is published by R as 6.2%; the previous JavaScript validator
incorrectly demanded 6.3%. No stored percentage or classification rule was changed.

Responses are read as a bounded stream. A synthetic response containing sixteen
1-MiB chunks is cancelled upon crossing the 8-MiB limit, instead of buffering all
sixteen chunks first. Declared-length and missing/incorrect-length cases are covered;
accepted bytes still undergo exact SHA-256 verification. Compare has a useful target
during initial loading, failure, empty data and before JavaScript executes.

## Researcher panel and publication

The coordinator publishes state changes instead of making the entire interface poll
once per second. A separate cooldown timer updates only the countdown and relevant
controls. Unchanged snapshots do not rebuild result tables or slides.

Cancellation is checked between downloads and preparation phases. An already running
network request can finish; subsequent work is skipped. Publication authorization,
expiry, single-worker coordination and reconciliation remain enforced.

Restoration reads the actual verified Pages snapshot directly, without waiting for an
optional GitHub lookup. A session arriving during another operation restores when the
coordinator becomes available, or reuses the freshly verified snapshot from that work.

Deployment confirmation fetches full results only after the expected manifest appears.
A deterministic sequence of two old manifests followed by the expected manifest now
downloads results once. Hash, identity, metadata and aggregate validation still apply.

## Build and privacy

The public scan examines every entry, including hidden files, and rejects unexpected
files and links. The source data folder permits exactly the two reviewed JSON files;
the artifact permits its entry HTML, those JSON files and hashed JavaScript/CSS assets.

CI builds once, checks the existing artifact in the browser, scans that tested artifact
and uploads it. Chromium installation uses the headless-shell option; it no longer
downloads the unused full browser. Local `npm run test:e2e` still builds automatically,
while `npm run test:e2e:built` tests an existing build.

No framework or dependency was added. Existing development-tool `picomatch` audit
findings remain documented in implementation-status.md; production JavaScript has no
runtime package dependencies. This pass does not claim a general hosting-capacity or
wall-clock speed guarantee.

## Verification

Before deployment, the complete R suite, 57 JavaScript tests and 11 browser tests
passed. The frozen rounding fixture was also checked independently by R. The public
artifact scan and an exact credential-value scan of all tracked/unignored source
files passed; the two public JSON files remain byte-for-byte unchanged.

The authenticated researcher browser check passed read recovery, fullscreen entry and
server-controlled exit, cooldown enforcement/re-enabling, logout and a second login
with correctly enabled controls. The coordinator regression renders a snapshot once
across five clock ticks, and once more only when the snapshot actually changes.
