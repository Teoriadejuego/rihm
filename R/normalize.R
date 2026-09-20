first_existing <- function(data, candidates, required = TRUE) {
  found <- candidates[candidates %in% names(data)]
  if (!length(found)) {
    if (required) {
      stop("Missing required column; expected one of: ", paste(candidates, collapse = ", "), call. = FALSE)
    }
    return(rep(NA_character_, nrow(data)))
  }
  data[[found[[1L]]]]
}

coalesce_existing <- function(data, candidates) {
  found <- candidates[candidates %in% names(data)]
  if (!length(found)) {
    stop("Missing required decision column; expected one of: ", paste(candidates, collapse = ", "), call. = FALSE)
  }
  values <- data[[found[[1L]]]]
  if (length(found) > 1L) {
    for (name in found[-1L]) {
      replacement <- data[[name]]
      empty <- is.na(values) | trimws(as.character(values)) == ""
      values[empty] <- replacement[empty]
    }
  }
  suppressWarnings(as.numeric(as.character(values)))
}

normalise_survey <- function(raw, scope, locations, session_code_column = "session_password") {
  if (!is.data.frame(raw) || !nrow(raw)) {
    stop("The ", scope, " survey returned no rows.", call. = FALSE)
  }

  modern_schema <- "dic11_19" %in% names(raw)
  if (modern_schema) {
    decision_map <- list(
      DP1 = c("dic10_6", "dic10_6_2"),
      DP2 = c("dic16_4", "dic16_4_2"),
      DP3 = c("dic10_18", "dic10_18_2"),
      DP4 = c("dic11_19", "dic11_19_2"),
      DP5 = c("dic12_4", "dic12_4_2"),
      DP6 = c("dic8_16", "dic8_16_2")
    )
    schema <- "dic_pairs"
  } else {
    decision_map <- list(
      DP1 = "DIC4", DP2 = "DIC5", DP3 = "DIC3",
      DP4 = "DIC6", DP5 = "DIC2", DP6 = "DIC1"
    )
    schema <- "DIC"
  }

  output <- data.frame(row_index = seq_len(nrow(raw)), stringsAsFactors = FALSE)
  for (name in names(decision_map)) {
    output[[name]] <- coalesce_existing(raw, decision_map[[name]])
  }
  output$gender_code <- suppressWarnings(as.numeric(as.character(first_existing(raw, c("gender", "Gender"), required = FALSE))))
  output$uni <- suppressWarnings(as.numeric(as.character(first_existing(raw, c("uni", "Uni"), required = FALSE))))
  output$response_id <- as.character(first_existing(raw, c("ResponseId", "responseId", "response_id"), required = FALSE))
  output$end_date <- as.character(first_existing(raw, c("EndDate", "endDate", "RecordedDate"), required = FALSE))
  output$finished <- as.character(first_existing(raw, c("Finished", "finished"), required = FALSE))
  output$session_code <- if (session_code_column %in% names(raw)) {
    trimws(as.character(raw[[session_code_column]]))
  } else {
    rep(NA_character_, nrow(raw))
  }

  match_index <- match(output$uni, locations$uni)
  output$country <- locations$country[match_index]
  output$scope <- scope
  output$source_schema <- schema
  output
}

filter_class_session <- function(data, session_code) {
  session_code <- trimws(as.character(session_code))
  if (!nzchar(session_code)) {
    stop("A class session code is required.", call. = FALSE)
  }
  if (all(is.na(data$session_code))) {
    stop("The class survey does not contain the configured session code column.", call. = FALSE)
  }
  keep <- !is.na(data$session_code) & tolower(data$session_code) == tolower(session_code)
  filtered <- data[keep, , drop = FALSE]
  if (!nrow(filtered)) {
    stop("No class responses match the supplied session code.", call. = FALSE)
  }
  filtered
}

filter_reference_locations <- function(data) {
  data[!is.na(data$country), , drop = FALSE]
}

