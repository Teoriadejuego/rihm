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
| Live publication | Hosted Update and publish generated publication `20261117T232755Z-b16fbc00`; the panel confirmed it on Pages |
| Live idempotency | Reusing identical aggregates produced no write or new publication, with mutation permission explicitly denied during the check |
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

The Shiny coordinator requires one application worker. The deployed application was
checked through the hosting API: maximum one Shiny worker and one starting instance.
Per-snapshot suppression does
not guarantee anonymity across successive public versions. Public history persists.

## Release verification

The first source release `567e745` passed [GitHub Actions](https://github.com/Teoriadejuego/rihm/actions/runs/44197528706)
and the new student site is served by Pages. The reconstructed researcher panel was
deployed to the existing shinyapps.io application; real login, full-screen teaching
and keyboard navigation were verified online. An online check then found a Shiny
control-event registration issue; five regression tests cover its correction.

The real publication [passed its own build and deployment](https://github.com/Teoriadejuego/rihm/actions/runs/44199602256).
The hosted panel reported “Published and confirmed on the student site” and signed
out successfully. A separate reader verified schema 2.0.0, matching publication IDs,
the semantic fingerprint and the SHA256 of the exact served results bytes.

The final control regression also verifies Shiny's requirement that each custom
message callback accepts one argument. A real local browser checked disabled controls
before cooldown, their later re-enabling, read recovery and server-requested fullscreen
exit. Deterministic test fixtures never replaced the public JSON files.

Final hosting bundle `12836354` was deployed and checked online: authentication,
restoring the actual student publication, slide keyboard navigation, server-controlled
fullscreen exit, cooldown state, zero JavaScript page errors and logout all passed.
The live student page was also checked without mocked responses on desktop and mobile:
the real publication rendered, filters made no additional requests, no private service
was contacted, and the layout had no horizontal overflow. Local preview servers were
stopped after verification; both online destinations remain available.

Both validation workflows pin Ubuntu 24.04 so GitHub's rolling `ubuntu-latest`
migration does not silently change their operating system. The 26.04 release runner
spent more than sixteen minutes downloading system dependencies before application
tests began. The pull-request workflow now installs the locked JavaScript dependencies
and runs the same JavaScript/browser checks as the Pages build; its obsolete Quarto
setup was removed.
