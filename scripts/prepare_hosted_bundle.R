# Run from the project root. The resulting directory is private: hosting.env
# contains credentials for the authenticated teacher service, never the site.
prepare_hosted_bundle <- function(project_root = ".", timestamp = Sys.time()) {
  fail <- function(message) stop(message, call. = FALSE)
  root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  inside_root <- function(path) {
    resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
    startsWith(tolower(resolved), paste0(tolower(root), "/"))
  }
  private_config <- file.path(root, "config", "hosting.Renviron")
  if (!file.exists(private_config) || dir.exists(private_config) || !inside_root(private_config)) {
    fail("Create the ignored config/hosting.Renviron before preparing a hosted bundle.")
  }
  allowed_settings <- c(
    "TEACHER_USERNAME", "TEACHER_PASSWORD", "GITHUB_PUBLICATION_TOKEN",
    "GITHUB_REPOSITORY", "GITHUB_PUBLICATION_BRANCH", "PAGES_BASE_URL",
    "QUALTRICS_API_KEY", "QUALTRICS_BASE_URL", "QUALTRICS_REFERENCE_SURVEY_ID",
    "QUALTRICS_CLASS_SURVEY_ID", "QUALTRICS_SESSION_COLUMN"
  )
  lines <- tryCatch(suppressWarnings(readLines(private_config, warn = FALSE)), error = function(error) NULL)
  if (is.null(lines)) fail("Could not read the private hosting configuration.")
  settings <- trimws(lines)
  settings <- settings[nzchar(settings) & !startsWith(settings, "#")]
  if (any(!grepl("^[A-Za-z][A-Za-z0-9_]*[[:space:]]*=", settings))) {
    fail("Private hosting configuration must contain one environment assignment per line.")
  }
  keys <- trimws(sub("=.*$", "", settings))
  if (anyDuplicated(keys) || any(!keys %in% allowed_settings)) {
    fail("Private hosting configuration contains duplicate or unsupported settings.")
  }
  if (!"TEACHER_PASSWORD" %in% keys) {
    fail("Set TEACHER_PASSWORD to a private password of at least 20 characters.")
  }
  # Renviron expansion must not obtain secrets from unrelated local variables.
  if (any(grepl("${", settings, fixed = TRUE))) {
    fail("Private hosting settings must contain literal values, not environment substitutions.")
  }
  original <- Sys.getenv(allowed_settings, unset = NA_character_)
  restore_environment <- function() {
    Sys.unsetenv(allowed_settings)
    present <- !is.na(original)
    if (any(present)) do.call(Sys.setenv, as.list(original[present]))
  }
  on.exit(restore_environment(), add = TRUE)
  Sys.unsetenv(allowed_settings)
  loaded <- tryCatch(withCallingHandlers(readRenviron(private_config),
    warning = function(warning) stop("Invalid private hosting configuration.", call. = FALSE)),
    error = function(error) FALSE)
  if (!isTRUE(loaded)) fail("Could not parse the private hosting configuration.")
  password <- Sys.getenv("TEACHER_PASSWORD", unset = "")
  if (nchar(password) < 20L || nchar(password, type = "bytes") > 1024L ||
      !nzchar(trimws(password)) || grepl("[[:cntrl:]]", password)) {
    fail("Set TEACHER_PASSWORD to a private password of at least 20 characters.")
  }
  password <- NULL
  restore_environment()

  modules <- list.files(file.path(root, "R"), pattern = "\\.R$", full.names = FALSE,
    recursive = FALSE, all.files = FALSE)
  if (!length(modules)) fail("No R application modules were found.")
  sources <- c("app.R", "admin/app.R", paste0("R/", sort(modules)), "DESCRIPTION",
    "config/reference_locations.csv", "config/hosting.Renviron")
  destinations <- sources
  destinations[destinations == "config/hosting.Renviron"] <- "hosting.env"
  source_paths <- file.path(root, sources)
  if (any(!file.exists(source_paths)) || any(dir.exists(source_paths)) ||
      !all(vapply(source_paths, inside_root, logical(1)))) {
    fail("A required application source is missing or outside the project.")
  }
  description <- tryCatch(read.dcf(file.path(root, "DESCRIPTION")), error = function(error) NULL)
  if (is.null(description) || !"Imports" %in% colnames(description) || nrow(description) != 1L) {
    fail("DESCRIPTION must declare the hosted application's R dependencies.")
  }

  staging <- file.path(root, "staging")
  if (!dir.exists(staging) && !dir.create(staging, showWarnings = FALSE)) fail("Could not create staging.")
  if (!inside_root(staging)) fail("The staging directory must remain inside the project.")
  stamp <- format(as.POSIXct(timestamp), "%Y%m%dT%H%M%SZ", tz = "UTC")
  if (length(stamp) != 1L || is.na(stamp) || !grepl("^[0-9]{8}T[0-9]{6}Z$", stamp)) fail("Invalid bundle timestamp.")
  bundle <- file.path(staging, paste0("teacher-hosted-", stamp))
  suffix <- 1L
  while (file.exists(bundle)) {
    suffix <- suffix + 1L
    bundle <- file.path(staging, paste0("teacher-hosted-", stamp, "-", suffix))
  }
  if (!dir.create(bundle, mode = "0700", showWarnings = FALSE)) fail("Could not create a fresh hosted bundle.")
  for (directory in c("admin", "R", "config")) {
    if (!dir.create(file.path(bundle, directory), mode = "0700", showWarnings = FALSE)) {
      fail("Could not prepare the hosted bundle directories.")
    }
  }
  # A fixed whitelist is copied file by file. Nothing is deleted or overwritten.
  copied <- file.copy(source_paths, file.path(bundle, destinations), overwrite = FALSE, copy.date = TRUE)
  if (!all(copied)) fail("The private hosted bundle is incomplete; prepare a fresh bundle after fixing the copy error.")
  suppressWarnings(Sys.chmod(file.path(bundle, "hosting.env"), mode = "0600"))
  actual <- list.files(bundle, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  if (!setequal(actual, destinations)) fail("Unexpected files were found in the hosted bundle.")
  normalizePath(bundle, winslash = "/", mustWork = TRUE)
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  if (length(arguments) > 1L) stop("Usage: Rscript scripts/prepare_hosted_bundle.R [project_root]", call. = FALSE)
  cat(prepare_hosted_bundle(if (length(arguments)) arguments[[1L]] else "."), "\n", sep = "")
}
