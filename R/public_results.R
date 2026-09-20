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
      source_snapshot_at_utc = format(as.POSIXct(source_snapshot_at_utc), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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

public_manifest <- function(results) {
  list(
    schema_version = results$metadata$schema_version,
    publication_id = results$metadata$publication_id,
    generated_at_utc = results$metadata$generated_at_utc
  )
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
  jsonlite::write_json(value, temporary, dataframe = "rows", na = "null", auto_unbox = TRUE, pretty = pretty)
  if (file.exists(path) && !file.remove(path)) stop("Could not replace ", path, call. = FALSE)
  if (!file.rename(temporary, path)) stop("Could not atomically write ", path, call. = FALSE)
  invisible(path)
}

write_public_snapshot <- function(results, project_root, secrets = character(), save_snapshot = TRUE) {
  assert_public_safe(results, secrets)
  data_path <- file.path(project_root, "student", "data", "public_results.json")
  manifest_path <- file.path(project_root, "student", "data", "public_manifest.json")
  atomic_write_json(results, data_path)
  atomic_write_json(public_manifest(results), manifest_path)

  if (isTRUE(save_snapshot)) {
    snapshot_path <- file.path(project_root, "snapshots", paste0(results$metadata$publication_id, ".json"))
    atomic_write_json(results, snapshot_path)
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

