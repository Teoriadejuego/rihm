new_publication_id <- function(time = Sys.time()) {
  stamp <- format(time, "%Y%m%dT%H%M%SZ", tz = "UTC")
  suffix <- substr(gsub("-", "", uuid::UUIDgenerate()), 1L, 8L)
  paste0(stamp, "-", suffix)
}

build_public_results <- function(class_data, reference_data, minimum_cell_size = 5L,
                                 source_snapshot_at_utc = Sys.time(), publication_id = NULL) {
  if (is.null(publication_id)) publication_id <- new_publication_id()
  aggregates <- aggregate_public_data(class_data, reference_data, minimum_cell_size)
  list(
    metadata = list(
      schema_version = "1.0.0",
      publication_id = publication_id,
      generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      source_snapshot_at_utc = format_utc_timestamp(source_snapshot_at_utc),
      minimum_cell_size = as.integer(minimum_cell_size),
      classification_note = paste(
        "Behaviour indicators reproduce the original overlapping rules.",
        "They are not mutually exclusive and percentages may sum to more than 100%."
      )
    ),
    cells = aggregates$cells,
    matrix_cells = aggregates$matrix_cells
  )
}

sha256_utf8 <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    stop("A single UTF-8 string is required for hashing.", call. = FALSE)
  }
  unname(unclass(as.character(openssl::sha256(charToRaw(enc2utf8(text))))))
}

canonical_public_table <- function(data) {
  if (is.list(data) && !is.data.frame(data) && !length(data)) return(list())
  if (!is.data.frame(data)) stop("Public cells must be a table.", call. = FALSE)
  if (!nrow(data)) return(list())
  dimensions <- intersect(c("scope", "country", "gender", "behaviour", "compassion_level", "envy_level"), names(data))
  data <- data[, sort(names(data), method = "radix"), drop = FALSE]
  if (length(dimensions)) {
    ordering <- do.call(order, c(lapply(data[dimensions], function(column) {
      if (is.character(column)) enc2utf8(column) else column
    }), list(method = "radix", na.last = TRUE)))
    data <- data[ordering, , drop = FALSE]
  }
  rownames(data) <- NULL
  data
}

public_content_fingerprint <- function(results) {
  # Operational timestamps and publication identity do not change the meaning
  # of a snapshot. Window bounds, rule versions and both aggregate tables do.
  metadata <- results$metadata
  transient <- c("publication_id", "generated_at_utc", "source_snapshot_at_utc",
    "class_source_at_utc", "reference_source_at_utc", "content_fingerprint", "rollback_of")
  metadata <- metadata[sort(setdiff(names(metadata), transient), method = "radix")]
  semantic <- list(metadata = metadata, cells = canonical_public_table(results$cells),
    matrix_cells = canonical_public_table(results$matrix_cells))
  sha256_utf8(as.character(jsonlite::toJSON(semantic, dataframe = "rows", na = "null",
    auto_unbox = TRUE, digits = NA, pretty = FALSE)))
}

build_latest_group_results <- function(class_data, reference_data, minimum_cell_size = 5L,
                                       window_start_utc, window_end_utc,
                                       class_source_at_utc, reference_source_at_utc,
                                       publication_id = NULL, generated_at_utc = Sys.time()) {
  results <- build_public_results(class_data, reference_data, minimum_cell_size,
    source_snapshot_at_utc = class_source_at_utc, publication_id = publication_id)
  results$metadata$schema_version <- "2.0.0"
  results$metadata$generated_at_utc <- format_utc_timestamp(generated_at_utc)
  results$metadata$window_start_utc <- format_utc_timestamp(window_start_utc)
  results$metadata$window_end_utc <- format_utc_timestamp(window_end_utc)
  results$metadata$selection_rule <- "latest_response_hour"
  results$metadata$class_source_at_utc <- format_utc_timestamp(class_source_at_utc)
  results$metadata$reference_source_at_utc <- format_utc_timestamp(reference_source_at_utc)
  results$metadata$classification_version <- "1.0.0"
  results$metadata$privacy_version <- "1.0.0"
  results$metadata$data_mode <- "qualtrics"
  results$metadata$content_fingerprint <- public_content_fingerprint(results)
  results
}

# The returned string is the exact public file content: UTF-8, no BOM and no
# newline added by the writer. Hash this string, not a separately rebuilt JSON.
serialize_public_results <- function(results) {
  enc2utf8(as.character(jsonlite::toJSON(results, dataframe = "rows", na = "null",
    null = "null", auto_unbox = TRUE, digits = NA, pretty = TRUE)))
}

public_manifest <- function(results, serialized_results = serialize_public_results(results)) {
  manifest <- list(
    schema_version = results$metadata$schema_version,
    publication_id = results$metadata$publication_id,
    generated_at_utc = results$metadata$generated_at_utc
  )
  if (identical(results$metadata$schema_version, "2.0.0")) {
    manifest$results_sha256 <- sha256_utf8(serialized_results)
  }
  manifest
}

assert_public_safe <- function(results, secrets = character()) {
  forbidden_names <- c(
    "session_code", "session_password", "response_id", "responseid", "recipientemail",
    "recipientfirstname", "recipientlastname", "ipaddress", "locationlatitude", "locationlongitude"
  )
  collect_names <- function(x) {
    output <- names(x)
    if (is.list(x)) output <- c(output, unlist(lapply(x, collect_names), use.names = FALSE))
    output
  }
  names_found <- tolower(unique(collect_names(results)))
  leaked_names <- intersect(forbidden_names, names_found)
  if (length(leaked_names)) {
    stop("Public result contains forbidden fields: ", paste(leaked_names, collapse = ", "), call. = FALSE)
  }

  serialised <- jsonlite::toJSON(results, dataframe = "rows", na = "null", auto_unbox = TRUE)
  secrets <- unique(secrets[!is.na(secrets) & nzchar(secrets)])
  leaked_secrets <- secrets[vapply(secrets, function(secret) grepl(secret, serialised, fixed = TRUE), logical(1))]
  if (length(leaked_secrets)) {
    stop("A private session value was found in the public result.", call. = FALSE)
  }
  invisible(TRUE)
}

atomic_write_json <- function(value, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "json-", tmpdir = dirname(path), fileext = ".tmp")
  jsonlite::write_json(value, temporary, dataframe = "rows", na = "null", null = "null", auto_unbox = TRUE, pretty = pretty)
  if (file.exists(path) && !file.remove(path)) stop("Could not replace ", path, call. = FALSE)
  if (!file.rename(temporary, path)) stop("Could not atomically write ", path, call. = FALSE)
  invisible(path)
}

atomic_write_utf8 <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "json-", tmpdir = dirname(path), fileext = ".tmp")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  writeBin(charToRaw(enc2utf8(text)), temporary)
  if (file.exists(path) && !file.remove(path)) stop("Could not replace public JSON.", call. = FALSE)
  if (!file.rename(temporary, path)) stop("Could not install public JSON.", call. = FALSE)
  invisible(path)
}

write_public_snapshot <- function(results, project_root, secrets = character(), save_snapshot = TRUE) {
  assert_public_safe(results, secrets)
  data_path <- file.path(project_root, "student", "data", "public_results.json")
  manifest_path <- file.path(project_root, "student", "data", "public_manifest.json")
  serialised <- serialize_public_results(results)
  atomic_write_utf8(serialised, data_path)
  atomic_write_json(public_manifest(results, serialised), manifest_path)

  if (isTRUE(save_snapshot)) {
    snapshot_path <- file.path(project_root, "snapshots", paste0(results$metadata$publication_id, ".json"))
    atomic_write_utf8(serialised, snapshot_path)
  }
  invisible(list(data = data_path, manifest = manifest_path))
}

read_public_snapshot <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}

prepare_rollback <- function(snapshot) {
  previous_id <- snapshot$metadata$publication_id
  snapshot$metadata$publication_id <- new_publication_id()
  snapshot$metadata$generated_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  snapshot$metadata$rollback_of <- previous_id
  snapshot
}

