deduplicate_responses <- function(data) {
  usable_id <- !is.na(data$response_id) & nzchar(trimws(data$response_id))
  duplicated_ids <- unique(data$response_id[usable_id & duplicated(data$response_id)])
  if (!length(duplicated_ids)) {
    return(list(data = data, duplicate_count = 0L, duplicate_ids = character()))
  }

  keep <- rep(TRUE, nrow(data))
  for (id in duplicated_ids) {
    positions <- which(data$response_id == id)
    dates <- parse_qualtrics_end_date(data$end_date[positions])
    winner <- if (all(is.na(dates))) tail(positions, 1L) else positions[which.max(dates)]
    keep[setdiff(positions, winner)] <- FALSE
  }
  list(
    data = data[keep, , drop = FALSE],
    duplicate_count = sum(!keep),
    duplicate_ids = duplicated_ids
  )
}

# Select from the deduplicated source before excluding incomplete/non-binary
# decisions. The latest response, even a statistically excluded one, anchors T.
prepare_latest_class_group <- function(raw, locations, session_code_column = "session_password") {
  normalised <- normalise_survey(raw, "class", locations, session_code_column,
    allow_recorded_date = FALSE)
  deduplicated <- deduplicate_responses(normalised)
  source <- deduplicated$data
  dates <- parse_qualtrics_end_date(source$end_date)
  valid <- !is.na(dates)
  if (!any(valid)) {
    stop("The class source has no valid EndDate values; no new snapshot was prepared.", call. = FALSE)
  }
  end <- max(dates[valid])
  start <- end - 3600
  selected <- valid & dates > start & dates <= end
  classified <- classify_preferences(source[which(selected), , drop = FALSE])
  selection <- list(
    selection_rule = "latest_response_hour",
    window_start_utc = format_utc_timestamp(start), window_end_utc = format_utc_timestamp(end),
    source_rows = nrow(normalised), deduplicated_rows = nrow(source),
    invalid_end_dates = sum(!valid), outside_window_rows = sum(valid & !selected),
    selected_rows = sum(selected)
  )
  diagnostics <- rbind(
    data.frame(metric = c("Source rows before deduplication", "Missing or invalid EndDate values excluded",
      "Dated responses outside the latest-response hour"),
      value = c(selection$source_rows, selection$invalid_end_dates, selection$outside_window_rows)),
    build_diagnostics(classified, deduplicated$duplicate_count)
  )
  list(data = classified, diagnostics = diagnostics, duplicate_ids = deduplicated$duplicate_ids,
    schema = unique(classified$source_schema), selection = selection)
}

build_diagnostics <- function(data, duplicate_count = 0L) {
  decision_values <- data[decision_columns]
  complete <- stats::complete.cases(decision_values)
  binary <- complete & apply(decision_values, 1L, function(row) all(row %in% c(0, 1)))
  data.frame(
    metric = c(
      "Rows after scope filtering", "Duplicate ResponseIds removed", "Complete binary responses",
      "Incomplete responses excluded", "Complete non-binary responses excluded",
      "Consistent responses", "Inconsistent responses"
    ),
    value = c(
      nrow(data), duplicate_count, sum(binary), sum(!complete), sum(complete & !binary),
      sum(data$consistent, na.rm = TRUE), sum(data$Inconsistent == 1, na.rm = TRUE)
    ),
    stringsAsFactors = FALSE
  )
}

prepare_survey <- function(raw, scope, locations, session_code_column, session_code = NULL) {
  normalised <- normalise_survey(raw, scope, locations, session_code_column)
  if (identical(scope, "class")) {
    normalised <- filter_class_session(normalised, session_code)
  } else {
    normalised <- filter_reference_locations(normalised)
    if (!nrow(normalised)) {
      stop("No international responses match the configured reference locations.", call. = FALSE)
    }
  }
  deduplicated <- deduplicate_responses(normalised)
  classified <- classify_preferences(deduplicated$data)
  list(
    data = classified,
    diagnostics = build_diagnostics(classified, deduplicated$duplicate_count),
    duplicate_ids = deduplicated$duplicate_ids,
    schema = unique(classified$source_schema)
  )
}

