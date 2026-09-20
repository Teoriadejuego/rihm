demo_session_code <- function() "DEMO-RIHM"

# This demonstration is generated entirely in memory. It never reads a survey
# export or contacts Qualtrics, and the ordinary pipeline protects its aggregates.
prepare_demo_candidate <- function(config, session_code = demo_session_code()) {
  if (length(session_code) != 1L || is.na(session_code) ||
      !identical(toupper(trimws(as.character(session_code))), demo_session_code())) {
    stop("The demonstration code is ", demo_session_code(), ".", call. = FALSE)
  }
  locations <- read_reference_locations(config)
  locations <- locations[!duplicated(locations$country), , drop = FALSE]
  if (!nrow(locations)) stop("The demonstration requires reference locations.", call. = FALSE)

  patterns <- expand.grid(rep(list(0:1), 6), KEEP.OUT.ATTRS = FALSE)
  names(patterns) <- decision_columns
  patterns <- classify_preferences(patterns)
  patterns <- patterns[patterns$consistent, , drop = FALSE]

  make_decisions <- function(seed, gender, uni) {
    repetitions <- 5L + (
      patterns$compassionincreas * seed + patterns$envyincreas * gender + seed * gender
    ) %% 7L
    rows <- patterns[rep(seq_len(nrow(patterns)), repetitions), decision_columns, drop = FALSE]
    # Complete, inconsistent decisions; then two partial and two non-binary rows.
    inconsistent <- as.data.frame(as.list(stats::setNames(c(1, 0, 1, 1, 1, 1), decision_columns)))
    rows <- rbind(rows, inconsistent[rep(1L, 5L + seed + gender), , drop = FALSE])
    partial <- rows[rep(1L, 2L), , drop = FALSE]
    partial$DP1 <- NA_real_
    non_binary <- rows[rep(1L, 2L), , drop = FALSE]
    non_binary$DP1 <- 2
    rows <- rbind(rows, partial, non_binary)
    rows$gender <- gender
    rows$uni <- uni
    rows
  }

  class_uni <- if ("Spain" %in% locations$country) {
    locations$uni[match("Spain", locations$country)]
  } else locations$uni[[1L]]
  class <- do.call(rbind, lapply(1:2, function(gender) make_decisions(1L, gender, class_uni)))
  reference <- do.call(rbind, lapply(seq_len(nrow(locations)), function(i) {
    do.call(rbind, lapply(1:2, function(gender) make_decisions(i + 2L, gender, locations$uni[[i]])))
  }))

  make_raw <- function(data, scope, columns) {
    raw <- data[decision_columns]
    names(raw) <- columns
    raw$gender <- data$gender
    raw$uni <- data$uni
    raw[[config$qualtrics$session_code_column]] <- demo_session_code()
    raw$ResponseId <- paste0("synthetic-", scope, "-", seq_len(nrow(raw)))
    raw$EndDate <- "2026-01-01 12:00:00"
    # The repeated row exercises the same deduplication used for real downloads.
    rbind(raw, raw[1L, , drop = FALSE])
  }
  downloaded <- list(
    class = make_raw(class, "class", c("dic10_6", "dic16_4", "dic10_18", "dic11_19", "dic12_4", "dic8_16")),
    reference = make_raw(reference, "reference", c("DIC4", "DIC5", "DIC3", "DIC6", "DIC2", "DIC1")),
    downloaded_at_utc = Sys.time()
  )
  candidate <- prepare_publication_candidate(downloaded, demo_session_code(), config)
  candidate$results$metadata$publication_id <- paste0("demo-", candidate$results$metadata$publication_id)
  candidate$results$metadata$data_mode <- "demonstration"
  candidate$results$metadata$data_note <- "Synthetic demonstration data generated locally; no real participants."
  assert_public_safe(candidate$results, secrets = c(session_code, demo_session_code()))
  candidate
}
