# Operations and recovery

Teachers use the [researcher panel](https://teoria-juegos.shinyapps.io/rihm-profesor/).
Students use the [student dashboard](https://teoriadejuego.github.io/rihm/).
Neither audience needs R installed. R and Node are developer/build requirements.

## Private configuration

The ignored `config/hosting.Renviron` supplies the hosting bundle. Keep the teacher
password, Qualtrics key/server, survey IDs and repository-scoped GitHub token there.
The GitHub token needs Contents read/write only for Teoriadejuego/rihm. Credential
inputs are absent from the product. `hosting.env` is a private deployment asset and
must never enter Git, student artifacts, screenshots or logs.

The old application source archive does not include its external .Renviron. The
configuration was recovered, with the owner's authorization, from another local
Shiny project and verified against both configured surveys. Its values and source
location are not part of this repository. Do not substitute demonstration data for
a real survey.

## Regular teaching

Sign in, open Project or Teach, and use the last published snapshot. Update and publish
refreshes both surveys after the shared three-minute cooldown. The latest response
hour is relative to the newest EndDate in the class database. An old response date is
not evidence of a failed publication. Read the separate acquisition/publication times.

If an update fails, retain the current snapshot and inspect the private diagnostics.
Do not retry a potentially accepted GitHub write blindly; reconciliation checks the
branch and matching publication. Demonstration is a preview with synthetic data and
does not publish automatically. Presentation mode pins the selected snapshot.

Cancellation is cooperative: an in-flight network request can finish, but the worker
checks cancellation before continuing to another download or preparation phase.
An already accepted publication write is still reconciled. Loading the latest group
reads the verified student publication directly; it does not wait for a GitHub API
lookup. Known pending publication commits remain separate from that confirmed view.

## Deployment

Use one Shiny worker. The coordinator is shared between sessions in that process;
adding worker processes would require a distributed lock and durable cooldown store.
Free-hosting sleep/restart incurs the conservative three-minute startup cooldown.
The panel is not a scheduler and does not fetch data when students open the website.

Build the private bundle with `scripts/prepare_hosted_bundle.R` and deploy with the
existing rsconnect account/application. Its file whitelist excludes staging, raw
downloads, snapshots and the repository. Inspect a new bundle manifest before upload.

GitHub Pages builds main through `.github/workflows/pages.yml`. It tests, builds and
scans before deployment. The deployment job checks the source commit is still main
to prevent an obsolete queued artifact from becoming the current site.

CI builds once, runs the browser checks against that artifact, then scans it before
upload. Only Chromium's headless shell is installed for these tests. The public input
directory permits exactly the two JSON files. The built site permits `index.html`,
those files under `data/`, and Vite-hashed JavaScript/CSS under `assets/`. Unexpected
files, hidden entries and symbolic links fail the scan. Adding another asset type
requires an explicit review and an update to this allowlist.

## Recovery

The two public JSON files form one publication. Restore them together from a validated
known-good Git commit using a new commit; never rewrite history. Validate their schema,
matching publication ID and v2 SHA256 before deploying. Keep source migrations in
separate commits from aggregate snapshots where possible.

On token expiration, replace only the private token and redeploy the teacher bundle.
On Qualtrics authentication failure, verify the key, server and permissions on both
surveys. Do not include a credential or response body in support messages.

## Reproducibility and limits

`package-lock.json` pins JavaScript dependencies; `renv.lock` records the R dependency
graph. `Rscript scripts/install_dependencies.R` is a convenient bootstrap; use
`renv::restore()` in an isolated development library for exact R versions.

Suppression protects each exported table under the stated rules. It does not remove
older public versions from Git and does not guarantee privacy under differencing
multiple releases. Do not interpret observational class/reference differences as
causal effects or representative population estimates.

Moving the teacher panel to Posit Connect Cloud is a future deployment option: verify
account support, private environment variables, the single-worker assumption, network
access, cold-start behaviour and bundle dependencies first. It is not required for
the existing shinyapps.io and Pages deployment.
