load_qualtrics_environment <- function(project_root) {
  if (identical(Sys.getenv("TEACHER_HOST_MODE"), "cloud")) return(invisible(TRUE))
  env_file <- file.path(project_root, ".Renviron")
  if (file.exists(env_file)) {
    readRenviron(env_file)
  }
  invisible(TRUE)
}

assert_qualtrics_environment <- function() {
  required <- c("QUALTRICS_API_KEY", "QUALTRICS_BASE_URL")
  missing <- required[!nzchar(Sys.getenv(required))]
  if (length(missing)) {
    stop(
      "Missing Qualtrics environment variables: ", paste(missing, collapse = ", "),
      ". Create .Renviron from .Renviron.example.",
      call. = FALSE
    )
  }
  validate_qualtrics_credentials(list(
    api_key = Sys.getenv("QUALTRICS_API_KEY"), base_url = Sys.getenv("QUALTRICS_BASE_URL")
  ))
  invisible(TRUE)
}

validate_qualtrics_credentials <- function(credentials) {
  scalar <- function(value) is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
  if (!is.list(credentials) || !scalar(credentials$api_key) ||
      nchar(credentials$api_key, type = "bytes") > 4096L ||
      grepl("[[:space:][:cntrl:]]", credentials$api_key)) {
    stop("Enter a valid Qualtrics API key.", call. = FALSE)
  }
  # qualtRics adds https:// itself. Restrict credentials to a single data-center
  # hostname on Qualtrics' domain; reject schemes, ports, paths and other hosts.
  if (!scalar(credentials$base_url) || nchar(credentials$base_url) > 77L ||
      !grepl("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.qualtrics\\.com$", credentials$base_url)) {
    stop("Enter the Qualtrics data-center hostname, for example fra1.qualtrics.com, without https:// or a path.", call. = FALSE)
  }
  invisible(TRUE)
}

remove_qualtrics_temp_directory <- function(path, temporary_root) {
  if (!dir.exists(path)) return(invisible(TRUE))
  resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
  root <- normalizePath(temporary_root, winslash = "/", mustWork = TRUE)
  compared <- if (.Platform$OS.type == "windows") tolower(resolved) else resolved
  root_compared <- if (.Platform$OS.type == "windows") tolower(root) else root
  if (!startsWith(compared, paste0(sub("/+$", "", root_compared), "/")) ||
      !startsWith(basename(resolved), "qualtrics-download-")) {
    stop("Refusing to remove an unexpected download directory.", call. = FALSE)
  }
  if (unlink(resolved, recursive = TRUE, force = TRUE) != 0L || dir.exists(resolved)) {
    stop("Could not remove the temporary survey download.", call. = FALSE)
  }
  invisible(TRUE)
}

fetch_survey_once <- function(survey_id, request = qualtRics::fetch_survey) {
  if (length(survey_id) != 1L || is.na(survey_id) || !grepl("^SV_[A-Za-z0-9]+$", survey_id)) {
    stop("Configure a valid Qualtrics survey ID before downloading real responses.", call. = FALSE)
  }
  if (!requireNamespace("qualtRics", quietly = TRUE)) {
    stop("The qualtRics package is required to download surveys.", call. = FALSE)
  }
  assert_qualtrics_environment()
  temporary_root <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  download_directory <- tempfile("qualtrics-download-", tmpdir = temporary_root)
  if (!dir.create(download_directory, mode = "0700")) {
    stop("Could not prepare temporary survey storage.", call. = FALSE)
  }
  on.exit(remove_qualtrics_temp_directory(download_directory, temporary_root), add = TRUE)
  request(
    surveyID = survey_id,
    convert = FALSE,
    label = FALSE,
    verbose = FALSE,
    tmp_dir = download_directory
  )
}

download_surveys_once <- function(config, credentials = NULL) {
  supplied <- !is.null(credentials)
  if (supplied) {
    validate_qualtrics_credentials(credentials)
    variables <- c("QUALTRICS_API_KEY", "QUALTRICS_BASE_URL")
    previous <- Sys.getenv(variables, unset = NA_character_)
    on.exit({
      absent <- names(previous)[is.na(previous)]
      if (length(absent)) Sys.unsetenv(absent)
      present <- previous[!is.na(previous)]
      if (length(present)) do.call(Sys.setenv, as.list(present))
    }, add = TRUE)
    # This operation is synchronous: no Shiny callbacks or background tasks
    # run while the per-request credentials occupy the process environment.
    Sys.setenv(QUALTRICS_API_KEY = credentials$api_key, QUALTRICS_BASE_URL = credentials$base_url)
  } else {
    load_qualtrics_environment(config$project_root)
  }
  download <- function() list(
      reference = fetch_survey_once(config$qualtrics$reference_survey_id),
      class = fetch_survey_once(config$qualtrics$class_survey_id),
      downloaded_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
  if (supplied || identical(Sys.getenv("TEACHER_HOST_MODE"), "cloud")) {
    tryCatch(suppressMessages(suppressWarnings(download())), error = function(error) {
      stop("Qualtrics download failed. Check the API key, data-center hostname, survey access and network connection.", call. = FALSE)
    })
  } else download()
}
