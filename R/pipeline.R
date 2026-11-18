prepare_publication_candidate <- function(downloaded, session_code, config) {
  locations <- read_reference_locations(config)
  class <- prepare_survey(
    downloaded$class, "class", locations,
    config$qualtrics$session_code_column, session_code
  )
  reference <- prepare_survey(
    downloaded$reference, "international", locations,
    config$qualtrics$session_code_column
  )
  results <- build_public_results(
    class$data,
    reference$data,
    config$privacy$minimum_cell_size,
    source_snapshot_at_utc = downloaded$downloaded_at_utc
  )
  assert_public_safe(results, secrets = session_code)
  list(results = results, class = class, reference = reference)
}

prepare_latest_group_candidate <- function(downloaded, config, check_active = function() TRUE) {
  assert_operation_active(check_active)
  locations <- read_reference_locations(config)
  if (!is.null(downloaded$export_time_zone) && !identical(downloaded$export_time_zone, "UTC")) {
    stop("Latest-group selection requires a UTC Qualtrics export.", call. = FALSE)
  }
  class <- prepare_latest_class_group(downloaded$class, locations,
    config$qualtrics$session_code_column %||% "session_password")
  assert_operation_active(check_active)
  reference <- prepare_survey(downloaded$reference, "international", locations,
    config$qualtrics$session_code_column %||% "session_password")
  assert_operation_active(check_active)
  results <- build_latest_group_results(class$data, reference$data,
    minimum_cell_size = config$privacy$minimum_cell_size,
    window_start_utc = class$selection$window_start_utc,
    window_end_utc = class$selection$window_end_utc,
    class_source_at_utc = downloaded$class_source_at_utc %||% downloaded$downloaded_at_utc,
    reference_source_at_utc = downloaded$reference_source_at_utc %||% downloaded$downloaded_at_utc)
  assert_operation_active(check_active)
  validate_github_public_results(results)
  list(results = results, class = class, reference = reference, selection = class$selection)
}

