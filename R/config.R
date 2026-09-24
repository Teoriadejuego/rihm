read_app_config <- function(project_root = ".", path = NULL) {
  if (identical(Sys.getenv("TEACHER_HOST_MODE"), "cloud")) {
    root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
    return(list(
      project_root = root,
      locations_file = file.path(root, "config", "reference_locations.csv"),
      qualtrics = list(
        reference_survey_id = Sys.getenv("QUALTRICS_REFERENCE_SURVEY_ID"),
        class_survey_id = Sys.getenv("QUALTRICS_CLASS_SURVEY_ID"),
        session_code_column = Sys.getenv("QUALTRICS_SESSION_COLUMN", "session_password")
      ),
      privacy = list(minimum_cell_size = 5L),
      publication = list(
        backend = "github_api",
        github_repository = Sys.getenv("GITHUB_REPOSITORY", "Teoriadejuego/rihm"),
        branch = Sys.getenv("GITHUB_PUBLICATION_BRANCH", "main"),
        pages_base_url = Sys.getenv("PAGES_BASE_URL", "https://teoriadejuego.github.io/rihm/"),
        verify_timeout_seconds = 300L
      )
    ))
  }
  if (is.null(path)) {
    path <- file.path(project_root, "config", "config.yml")
  }
  if (!file.exists(path)) {
    stop(
      "Missing local configuration: ", path,
      ". Copy config/config.example.yml to config/config.yml and edit it.",
      call. = FALSE
    )
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The yaml package is required.", call. = FALSE)
  }

  config <- yaml::read_yaml(path)
  required <- c(
    config$qualtrics$reference_survey_id,
    config$qualtrics$class_survey_id,
    config$qualtrics$session_code_column,
    config$privacy$minimum_cell_size,
    config$publication$branch
  )
  if (any(vapply(required, is.null, logical(1)))) {
    stop("config/config.yml is missing one or more required settings.", call. = FALSE)
  }

  config$privacy$minimum_cell_size <- as.integer(config$privacy$minimum_cell_size)
  if (is.na(config$privacy$minimum_cell_size) || config$privacy$minimum_cell_size < 2L) {
    stop("privacy.minimum_cell_size must be an integer of at least 2.", call. = FALSE)
  }
  config$project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  config$locations_file <- file.path(config$project_root, "config", "reference_locations.csv")
  config
}

read_reference_locations <- function(config) {
  locations <- utils::read.csv(config$locations_file, stringsAsFactors = FALSE)
  if (!identical(names(locations), c("uni", "country"))) {
    stop("reference_locations.csv must contain exactly uni,country.", call. = FALSE)
  }
  locations$uni <- suppressWarnings(as.numeric(locations$uni))
  if (anyNA(locations$uni) || any(!nzchar(locations$country))) {
    stop("reference_locations.csv contains invalid rows.", call. = FALSE)
  }
  unique(locations)
}
