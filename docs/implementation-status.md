# Implementation evidence

Verification date: 2026-11-18 (Europe/Madrid).

| Requirement | Evidence |
| --- | --- |
| Database-relative latest group | R boundary, historical-data, invalid-anchor and UTC/DST regression tests pass |
| Original classification | Fixed independent oracle covers all 64 binary decision patterns |
| Contract and privacy | R regression suite, exact-byte manifest scan, suppression and strict-field validation pass |
| Researcher coordination | Tests cover shared cooldown, startup wait, cancellation, disconnect cleanup, asynchronous work and pinned presentation |
| Published versus committed | Researcher reads and verifies the actual Pages files; pending Git commits do not replace the confirmed view |
| JavaScript reader and teacher controls | 34 unit tests pass, including v1/v2 parsing, refresh integrity and Shiny control lifecycle |
| Student browser flows | 8 Playwright E2E tests pass on the compiled site under `/rihm/` |
| Accessibility | Automated axe checks pass at desktop/mobile sizes; visual inspection completed, not a full human accessibility audit |
| Researcher browser | Real private login, five sections, all twelve slides, synthetic preview, hidden credential inputs and logout checked |
| Real source integration | Both Qualtrics surveys accessible; real candidate passes contract and privacy checks |
| Cross-runtime integration | R-produced real aggregate JSON accepted and rendered by the JavaScript reader |
| Static delivery | 30 clients: 150/150 HTTP 200; 60: 300/300; 200: 1000/1000 with five resources per client |
| Credential isolation | Exact private values absent from every tracked/unignored source file; private environment files remain ignored |
| Specialist specifications | 20 role prompts, each with exactly 20 acceptance points; 400 total |

The real source check selects 2026-09-24 12:46:03–13:46:03 UTC. This is the last
hour in the class database, not the hour before the verification clock time.

The first 200-client run against Python's default development server had 24 transport
failures. A local threaded server with a 512-entry connection queue passed all 1000
requests in 0.69 seconds. These are local static delivery measurements, not a hosted
capacity guarantee or a simulation of browser rendering.

## Execution responsibilities

The data/publication agent implemented temporal selection, contract v2 and publication,
then independently reviewed the cross-component interfaces. The researcher agent built
the panel, slide deck, coordinator and hosted-bundle whitelist. The student agent built
the browser application and JS/E2E checks. The coordinating agent integrated CI, privacy
artifact checks, dependency records, documentation, the independent statistical oracle,
credential recovery, real-data integration and browser/load verification.

The twenty profiles are specifications distributed across these implementation streams;
they do not claim twenty independent people performed reviews.

## Dependency and operational limits

The production JavaScript dependency audit reports zero vulnerabilities. A high-severity
ReDoS advisory in `picomatch` remains in development tooling, propagated through five
dependency entries; the package registry offered no patched release during verification.
Those packages are build/test tools and are not shipped in the browser bundle. Their
glob patterns are repository-controlled. Recheck the advisory when updating the lockfile.

The Shiny coordinator requires one application worker. Per-snapshot suppression does
not guarantee anonymity across successive public versions. Public history persists.

## Release verification

The first source release `567e745` passed [GitHub Actions](https://github.com/Teoriadejuego/rihm/actions/runs/44197528706)
and the new student site is served by Pages. The reconstructed researcher panel was
deployed to the existing shinyapps.io application; real login, full-screen teaching
and keyboard navigation were verified online. An online check then found a Shiny
control-event registration issue; five regression tests cover its correction.

Real publication verification will be recorded after the corrected panel is deployed.
Deterministic test fixtures have not replaced the public JSON files.
