# Mini-dictator classroom dashboard

Live dashboard: [teoriadejuego.github.io/rihm](https://teoriadejuego.github.io/rihm/).

This project replaces a shared Shiny application with two separate components:

- a password-protected Shiny publisher used only by the teacher, hosted on shinyapps.io or run locally; and
- a static Quarto dashboard that can be opened simultaneously by the whole class, regardless of whether a particular group is smaller or larger than the original estimate.

In local mode, Qualtrics credentials, session codes and row-level survey data remain on the teacher's computer. In hosted mode, the private teacher session processes them on shinyapps.io. GitHub receives only privacy-protected aggregate JSON and static site source.

## Online teacher panel

The hosted panel does not require R on the teacher's computer. Sign in with the private teacher credentials; the student dashboard remains public and independent of Shiny.

For a test, select **Demonstration: synthetic responses**, enter `DEMO-RIHM`, then **Load demonstration**. Review the aggregate cells, confirm the review, and use **Validate aggregate data**. This does not publish or replace the student snapshot.

The Qualtrics API key, data-center hostname and two survey IDs are configured privately on the server at deployment. Publication uses a GitHub fine-grained personal access token restricted to this repository with **Contents: Read and write**. These settings are read only from the server environment: no credential fields or values are sent to the browser. Sign in and enter the class session code to work; no API keys need to be entered for each session. Never paste credentials into an issue, commit, or the public student page.

The hosted publisher commits only the two public JSON files through the GitHub API. GitHub Actions then runs tests, renders, scans and deploys the student dashboard. Snapshot history is read from GitHub commits; no durable server filesystem is required. A failed deployment leaves the last successful Pages version online. Login expires after 15 minutes of inactivity; five failed logins lock the R process for five minutes. Use one worker for the teacher app.

For maintainers: copy `config/hosting.Renviron.example` to ignored `config/hosting.Renviron`, configure a unique teacher password of at least 20 characters, the survey IDs, `QUALTRICS_API_KEY`, `QUALTRICS_BASE_URL` and `GITHUB_PUBLICATION_TOKEN`, then run `Rscript scripts/prepare_hosted_bundle.R`. Deploy the printed bundle directory with `rsconnect::deployApp(..., appName = "rihm-profesor", account = "teoria-juegos", server = "shinyapps.io")`. The bundle includes private `hosting.env`; keep it outside public Git. No raw data, Git working tree, local `.Renviron`, or local `config.yml` is bundled. Updating a server credential requires a fresh private bundle and redeployment.

## First-time setup

1. Install R 4.3 or later, Quarto, Git and Git Credential Manager.
2. Run `Rscript scripts/install_dependencies.R`.
3. Copy `.Renviron.example` to `.Renviron` and add the Qualtrics API key and base URL.
4. Review the ignored local file `config/config.yml`. The two survey IDs from the original application are already entered locally.
5. Create an empty GitHub repository, enable **Settings → Pages → Source: GitHub Actions**, then connect and push the existing local `main` branch:

   ```powershell
   git remote add origin https://github.com/ACCOUNT/REPOSITORY.git
   git push -u origin main
   ```

6. Set `publication.pages_base_url` in `config/config.yml` to the Pages URL. Authenticate Git once through Git Credential Manager.

The local `config/config.yml`, `.Renviron`, raw downloads, staging files and snapshots are ignored by Git.

## Teacher workflow

Start the local panel from the project root:

```powershell
Rscript scripts/start_teacher.R
```

The teacher panel is available at `http://127.0.0.1:8124/` on the teacher's computer.

Then:

1. Enter the class session code and click **Download once from Qualtrics**.
2. Review the private diagnostics and the exact aggregate cells that may become public.
3. Confirm the review and click **Validate and render locally** if a dry run is wanted.
4. Click **Publish to GitHub Pages**. The panel tests, renders and scans the candidate, commits only the two public JSON files, pushes them, and checks the published manifest.
5. If necessary, select a local snapshot and republish it. Rollback creates a new commit and does not rewrite Git history.

The initial source-code commit is already present locally. After the first remote push, classroom-result publications are handled by the panel.

## Try the demonstration without Qualtrics

In the local teacher panel, select **Demonstration: synthetic responses**, use code
`DEMO-RIHM`, and click **Load demonstration**. This runs generated responses through
the same normalisation, classification and privacy checks as a real download.
The preview includes both survey schemas, six reference countries, gender filters,
and examples of invalid and duplicate responses in the private diagnostics.

After reviewing the preview, the usual validation and publication buttons work.
A published demonstration is explicitly labelled as synthetic on the student page;
it replaces the current public snapshot. It requires no Qualtrics credentials.
To return to real survey data, select **Qualtrics: real responses**, enter a real
session code and download and publish that candidate.

For a separate local student preview without changing the public snapshot, run
`Rscript scripts/preview_demo.R`, then serve `staging/demo-preview/student/_site`
with a local HTTP server. This preview never pushes to GitHub.

## Classification and denominators

The project deliberately reproduces the original rules for `Selfish`, `Spiteful`, `Egalitarian`, `dp_efficiency`, `Altruist`, `Ineqseek`, `Antisocial` and `Inconsistent`.

- `Altruist`, `Egalitarian`, `Selfish` and `Antisocial` are overlapping indicators. Their percentages are calculated over consistent responses and may sum to more than 100%.
- `Inconsistent` is calculated over complete binary responses.
- `dp_efficiency` is retained and regression-tested but is not displayed because the current rule is identical to `Altruist`.
- Partial and non-binary responses are excluded from public calculations and reported only in the teacher's diagnostics.

## Privacy model

Every public cell is suppressed when its count, denominator or complementary count is below 5. Secondary suppression hides an additional related cell when a gender or country total would otherwise reveal the protected value. Suppressed cells contain `null`, not the underlying number.

A final cross-table check adds suppression when protected small values can be reconstructed by linear combinations of the published behaviour cells, matrix cells and sample sizes, including combinations across filters.

`student/data/public_results.json` contains only publication metadata, aggregate behaviour cells and aggregate compassion × envy matrix cells. The pre-publish scan rejects row-level identifiers, session fields and supplied session-code values.

## Verification commands

```powershell
Rscript scripts/run_tests.R
Rscript scripts/render_site.R
Rscript scripts/scan_public.R
```

To test a representative concurrent class size, serve `student/_site` locally in one terminal and pass the desired number of simulated connections to the checker in another:

```powershell
python -m http.server 8000 --directory student/_site
Rscript scripts/check_concurrent_connections.R http://127.0.0.1:8000/ 60
```

The final argument is only a test parameter; use a smaller or larger value to match the expected class. It is not an application limit.

The static dashboard makes no request to Qualtrics or Shiny. After its aggregate JSON is loaded, filtering and chart updates run entirely in the browser.

## Public data contract

`public_results.json` has schema version `1.0.0`:

- `metadata`: publication ID, UTC generation/source times, suppression threshold and classification note.
- `cells`: scope, country, gender, behaviour, count, denominator, percentage, denominator type, complete/consistent sample sizes and suppression flag.
- `matrix_cells`: scope, country, gender, compassion level, envy level, count, denominator, percentage and suppression flag.

`public_manifest.json` exposes only the schema version, publication ID and generation time so the local panel can confirm that GitHub Pages serves the requested snapshot.
