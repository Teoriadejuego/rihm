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

