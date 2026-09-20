load_qualtrics_environment <- function(project_root) {
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
  invisible(TRUE)
}

fetch_survey_once <- function(survey_id) {
  if (!requireNamespace("qualtRics", quietly = TRUE)) {
    stop("The qualtRics package is required to download surveys.", call. = FALSE)
  }
  assert_qualtrics_environment()
  qualtRics::fetch_survey(
    surveyID = survey_id,
    convert = FALSE,
    label = FALSE,
    force_request = TRUE
  )
}

download_surveys_once <- function(config) {
  load_qualtrics_environment(config$project_root)
  list(
    reference = fetch_survey_once(config$qualtrics$reference_survey_id),
    class = fetch_survey_once(config$qualtrics$class_survey_id),
    downloaded_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}
