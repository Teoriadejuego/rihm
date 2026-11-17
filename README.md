# RIHM Decision Lab

[Researcher panel](https://teoria-juegos.shinyapps.io/rihm-profesor/) ·
[Student dashboard](https://teoriadejuego.github.io/rihm/)

RIHM has two independent parts. The private Shiny researcher panel explains the
experiment, provides twelve teaching slides and updates the public aggregates. The
JavaScript student dashboard explores and compares the last published snapshot.
Teachers and students need only a browser.

## Researcher workflow

1. Sign in with the private teacher account.
2. Open **Project** for the protocol or **Teach** for slides and presenter notes.
3. Open **Latest group** to inspect the most recent snapshot.
4. In **Update**, choose **Update and publish** after the shared three-minute cooldown.
5. Review acquisition/publication status and the private **Diagnostics**.

The update downloads both configured Qualtrics surveys once, validates them, applies
classification and suppression, and publishes the aggregate JSON automatically.
Unchanged public content creates no duplicate publication. Failures preserve the
last valid public snapshot. A server restart starts a conservative three-minute wait.

**Load private demonstration** is an isolated synthetic preview. It does not require
Qualtrics or replace the public snapshot. Presentation mode pins the selected public
snapshot so an update cannot change the results midway through a slide explanation.

Credentials are read from private server configuration; there are no API-key inputs
in the page. Login expires after fifteen idle minutes. Use one Shiny worker: the
coordinator and cooldown are shared by sessions within that process.

## What “latest group” means

Let **T** be the maximum valid EndDate in the normalized, deduplicated class database.
The group includes responses in **(T − 3600 seconds, T]**, regardless of how old T is.
The lower boundary is excluded and upper-boundary ties are included. Determine T
before excluding incomplete or non-binary answers. Do not fall back to an older
group if the selected group is unusable. RecordedDate and session codes do not select it.

Qualtrics exports are requested in UTC. The reference uses all valid mapped
international responses. Response interval, acquisition time and publication time
are displayed separately. Students check for updates every sixty seconds while the
page is visible and when returning to it; filtering then runs entirely in their browser.

## Classification and privacy

The original Selfish, Spiteful, Egalitarian, dp_efficiency, Altruist, Ineqseek,
Antisocial and Inconsistent rules are retained. Altruist, Egalitarian, Selfish and
Antisocial overlap and use consistent responses as their denominator. Inconsistent
uses complete binary responses. dp_efficiency remains tested but is not plotted
separately because its current rule equals Altruist.

Counts, denominators and complementary counts below five are suppressed. Secondary
and cross-table suppression protect related cells. Suppressed numeric fields are
null, never hidden values. Partial and non-binary records appear only in private
diagnostics. GitHub receives aggregate JSON and static source, not row-level responses.

These safeguards apply to each snapshot. They do not guarantee anonymity against
comparisons between historical releases; Git retains old public versions.

## Developer setup and verification

Install R 4.3 or newer, Node.js 24, npm and Git. Quarto is no longer required.

```powershell
Rscript scripts/install_dependencies.R
npm ci
Rscript scripts/run_tests.R
npm test
Rscript scripts/render_site.R
Rscript scripts/scan_public.R
npx playwright install chromium
npm run test:e2e
```

`package-lock.json` pins JavaScript versions. `renv.lock` records the R dependency
graph; use `renv::restore()` in an isolated library to reproduce it. To update that
record intentionally, run `Rscript scripts/snapshot_dependencies.R`.

Local development uses ignored `.Renviron` and `config/config.yml`. Hosted deployment
uses ignored `config/hosting.Renviron`; start from the corresponding example file.
The private hosted bundle is created by `Rscript scripts/prepare_hosted_bundle.R`.
It contains `hosting.env`, which must never enter Git or student artifacts.

For local UI development:

```powershell
Rscript -e "shiny::runApp('admin', launch.browser = TRUE)"
npm run dev
```

The local teacher mode is for development on the owner's computer. The hosted entry
point enables server-side authentication. See [operations](docs/operations.md) for
deployment, credential rotation and recovery.

To check static delivery with representative class sizes, serve the built site:

```powershell
python scripts/serve_student_site.py --port 8000
```

Then in a second terminal:

```powershell
Rscript scripts/check_concurrent_connections.R http://127.0.0.1:8000/ 30
Rscript scripts/check_concurrent_connections.R http://127.0.0.1:8000/ 60
Rscript scripts/check_concurrent_connections.R http://127.0.0.1:8000/ 200
```

Each simulated client requests the HTML, referenced JavaScript/CSS, manifest and
results. This checks static delivery, not a guaranteed application capacity limit.

## Public contract

`student/data/public_results.json` schema 2.0.0 contains metadata, behaviour cells
and compassion × envy matrix cells. Metadata includes the historical response
interval, selection rule, separate acquisition times, rule versions and semantic
fingerprint. `public_manifest.json` includes the publication ID and SHA256 of the
exact results bytes. Both files are committed together.

The reader accepts legacy 1.0.0, including its initial empty snapshot, without
inventing a response interval. Invalid or mismatched new content never replaces
the last valid browser view.

See the [approved plan](docs/rebuild-plan.md), [twenty specialist prompts](docs/senior-prompts/README.md)
and [implementation evidence](docs/implementation-status.md).
