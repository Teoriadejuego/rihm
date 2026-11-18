# GitHub-only publication for a hosted teacher panel. No working tree, Git,
# Quarto, survey export, or local snapshot is needed by this module.
github_scalar_text <- function(value, maximum = 200L) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    nzchar(value) && nchar(value, type = "bytes") <= maximum &&
    !grepl("[[:cntrl:]]", value)
}

github_publication_target <- function(config, token) {
  if (!github_scalar_text(token, 4096L) || grepl("[[:space:]]", token)) {
    stop("GITHUB_PUBLICATION_TOKEN is missing or invalid.", call. = FALSE)
  }
  repository <- config$publication$github_repository
  branch <- config$publication$branch
  if (!github_scalar_text(repository) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*$", repository) ||
      grepl("\\.git$", repository)) {
    stop("publication.github_repository must be owner/repository.", call. = FALSE)
  }
  if (!github_scalar_text(branch) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9._/-]*$", branch) ||
      grepl("//|\\.\\.|\\.$|/\\.|\\.lock($|/)|/$|^refs/", branch)) {
    stop("publication.branch is invalid.", call. = FALSE)
  }
  list(repository = repository, branch = branch, path = paste0("/repos/", repository))
}

github_require_sha <- function(value) {
  if (!github_scalar_text(value, 40L) || !grepl("^[a-f0-9]{40}$", value)) {
    stop("GitHub returned an invalid object reference.", call. = FALSE)
  }
  value
}

# Injectable transport contract: (method, path, token, body = NULL) ->
# list(status = integer HTTP status, body = decoded JSON). All errors and
# warnings from transport are replaced before reaching the teacher's panel.
github_api_request <- function(method, path, token, body = NULL) {
  tryCatch(suppressWarnings({
    request <- httr2::request(paste0("https://api.github.com", path))
    request <- httr2::req_method(request, method)
    request <- httr2::req_auth_bearer_token(request, token)
    request <- httr2::req_headers(request,
      Accept = "application/vnd.github+json", `X-GitHub-Api-Version` = "2026-03-10"
    )
    request <- httr2::req_user_agent(request, "Mini-dictator-teacher-publisher")
    request <- httr2::req_timeout(request, 30)
    request <- httr2::req_options(request, followlocation = FALSE)
    request <- httr2::req_error(request, is_error = function(response) FALSE)
    if (!is.null(body)) request <- httr2::req_body_json(request, body, auto_unbox = TRUE)
    response <- httr2::req_perform(request)
    status <- httr2::resp_status(response)
    list(status = status, body = if (status >= 200L && status < 300L) {
      httr2::resp_body_json(response, simplifyVector = FALSE)
    } else NULL)
  }), error = function(error) {
    stop("GitHub transport failed; no automatic retry was attempted.", call. = FALSE)
  })
}

github_call <- function(request, method, path, token, body = NULL, expected = 200L) {
  response <- tryCatch(
    suppressWarnings(request(method = method, path = path, token = token, body = body)),
    error = function(error) NULL
  )
  if (is.null(response)) {
    stop("GitHub request failed; check the publication state before retrying.", call. = FALSE)
  }
  status <- response$status
  if (!is.numeric(status) || length(status) != 1L || is.na(status) ||
      status < 100L || status > 599L || status != as.integer(status)) {
    stop("GitHub returned an invalid response.", call. = FALSE)
  }
  if (!(status %in% expected)) {
    if (method == "PATCH" && status %in% c(409L, 422L)) {
      stop("GitHub rejected the branch update (HTTP ", status,
        "); it may have changed. Nothing was force-updated or retried.", call. = FALSE)
    }
    stop("GitHub request failed (HTTP ", status, "); no automatic retry was attempted.", call. = FALSE)
  }
  if (!is.list(response$body)) stop("GitHub returned an invalid response.", call. = FALSE)
  response$body
}

validate_github_public_results <- function(results, secrets = character(), allow_unpublished = FALSE) {
  invalid <- function() stop("Publication must contain only valid protected aggregate data.", call. = FALSE)
  exact_names <- function(value, expected) {
    !is.null(names(value)) && !anyDuplicated(names(value)) && setequal(names(value), expected)
  }
  if (!is.list(results) || !exact_names(results, c("metadata", "cells", "matrix_cells"))) invalid()
  metadata <- results$metadata
  if (!is.list(metadata) || !github_scalar_text(metadata$schema_version, 20L)) invalid()
  required <- c("schema_version", "publication_id", "generated_at_utc", "source_snapshot_at_utc",
    "minimum_cell_size", "classification_note")
  optional <- c("rollback_of", "data_mode", "data_note")
  v2 <- identical(metadata$schema_version, "2.0.0")
  if (v2) required <- c(required, "window_start_utc", "window_end_utc", "selection_rule",
    "class_source_at_utc", "reference_source_at_utc", "classification_version", "privacy_version",
    "content_fingerprint", "data_mode")
  if (!is.list(metadata) || anyDuplicated(names(metadata)) ||
      !all(required %in% names(metadata)) || any(!names(metadata) %in% c(required, optional))) invalid()
  if (!metadata$schema_version %in% c("1.0.0", "2.0.0")) invalid()
  unpublished <- isTRUE(allow_unpublished) && !v2 &&
    identical(metadata$publication_id, "not-published") && is.null(metadata$generated_at_utc) &&
    is.null(metadata$source_snapshot_at_utc) && length(results$cells) == 0L && length(results$matrix_cells) == 0L
  for (name in setdiff(names(metadata), "minimum_cell_size")) {
    if (unpublished && name %in% c("generated_at_utc", "source_snapshot_at_utc")) next
    if (!github_scalar_text(metadata[[name]], if (name %in% c("classification_note", "data_note")) 1000L else 120L)) invalid()
  }
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", metadata$publication_id)) invalid()
  dates <- c("generated_at_utc", "source_snapshot_at_utc", if (v2) c("window_start_utc", "window_end_utc",
    "class_source_at_utc", "reference_source_at_utc"))
  for (name in dates) {
    if (unpublished) next
    value <- metadata[[name]]
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z$", value) ||
        is.na(parse_qualtrics_end_date(value))) invalid()
  }
  if (v2 && (!identical(metadata$selection_rule, "latest_response_hour") ||
      !identical(metadata$classification_version, "1.0.0") || !identical(metadata$privacy_version, "1.0.0") ||
      !identical(metadata$data_mode, "qualtrics") ||
      !grepl("^[a-f0-9]{64}$", metadata$content_fingerprint) ||
      abs(as.numeric(difftime(parse_qualtrics_end_date(metadata$window_end_utc),
        parse_qualtrics_end_date(metadata$window_start_utc), units = "secs")) - 3600) > 1e-6)) invalid()
  minimum <- metadata$minimum_cell_size
  if (!is.numeric(minimum) || length(minimum) != 1L || is.na(minimum) ||
      !is.finite(minimum) || minimum < 5L || minimum != floor(minimum)) invalid()
  if (v2 && (!is.data.frame(results$cells) || !nrow(results$cells) ||
      !is.data.frame(results$matrix_cells) || !nrow(results$matrix_cells))) invalid()
  fields <- list(
    cells = c("scope", "country", "gender", "behaviour", "count", "denominator_n", "percentage",
      "denominator_type", "n_complete", "n_consistent", "suppressed"),
    matrix_cells = c("scope", "country", "gender", "compassion_level", "envy_level", "count",
      "denominator_n", "percentage", "suppressed")
  )
  for (table in names(fields)) {
    data <- results[[table]]
    if (is.list(data) && !is.data.frame(data) && !length(data)) next
    if (!is.data.frame(data) || !exact_names(data, fields[[table]])) invalid()
    if (!nrow(data)) next
    text_fields <- intersect(c("scope", "country", "gender", "behaviour", "denominator_type"), names(data))
    for (name in text_fields) {
      if (!is.character(data[[name]]) || anyNA(data[[name]]) ||
          any(!nzchar(data[[name]])) || any(nchar(data[[name]], type = "bytes") > 120L) ||
          any(grepl("[[:cntrl:]]", data[[name]]))) invalid()
    }
    if (any(!data$scope %in% c("class", "international")) ||
        any(!data$gender %in% c("all", "female", "male")) ||
        any(data$scope == "class" & data$country != "Class") ||
        !is.logical(data$suppressed) || anyNA(data$suppressed)) invalid()
    if (table == "cells") {
      if (any(!data$behaviour %in% c("altruist", "egalitarian", "selfish", "antisocial", "inconsistent")) ||
          any(data$denominator_type != ifelse(data$behaviour == "inconsistent", "complete", "consistent"))) invalid()
    } else {
      for (name in c("compassion_level", "envy_level")) {
        if (!is.numeric(data[[name]]) || anyNA(data[[name]]) || any(!data[[name]] %in% 1:4)) invalid()
      }
    }
    numbers <- intersect(c("count", "denominator_n", "percentage", "n_complete", "n_consistent"), names(data))
    for (name in numbers) {
      values <- data[[name]]
      # JSON null-only columns are logical NA after decoding a snapshot.
      if (!(is.numeric(values) || (is.logical(values) && all(is.na(values))))) invalid()
      if (any(!is.na(values) & (!is.finite(values) | values < 0)) ||
          any(!is.na(values[data$suppressed]))) invalid()
      if (name != "percentage" && any(values != floor(values), na.rm = TRUE)) invalid()
    }
    visible <- data[!data$suppressed, , drop = FALSE]
    if (anyNA(visible[c("count", "denominator_n", "percentage")]) ||
        any(visible$count < minimum | visible$denominator_n < minimum |
          visible$denominator_n - visible$count < minimum) ||
        any(abs(visible$percentage - round(100 * visible$count / visible$denominator_n, 1)) > 1e-7)) invalid()
    if (table == "cells" && (anyNA(visible$n_consistent) ||
        any(visible$n_consistent > visible$n_complete, na.rm = TRUE) ||
        any(visible$denominator_type == "consistent" & visible$denominator_n != visible$n_consistent) ||
        any(visible$denominator_type == "complete" &
          (is.na(visible$n_complete) | visible$denominator_n != visible$n_complete)))) invalid()
    if (table == "cells" && any(visible$behaviour == "inconsistent" &
      visible$count != visible$n_complete - visible$n_consistent)) invalid()
    dimensions <- setdiff(fields[[table]], c(numbers, "suppressed"))
    if (anyDuplicated(data[dimensions])) invalid()
  }
  if (v2) {
    slices <- unique(results$cells[c("scope", "country", "gender")])
    matrix_slices <- unique(results$matrix_cells[c("scope", "country", "gender")])
    if (!identical(canonical_public_table(slices), canonical_public_table(matrix_slices))) invalid()
    for (i in seq_len(nrow(slices))) {
      matching <- function(data) data$scope == slices$scope[[i]] &
        data$country == slices$country[[i]] & data$gender == slices$gender[[i]]
      behaviours <- results$cells$behaviour[matching(results$cells)]
      matrix <- results$matrix_cells[matching(results$matrix_cells), , drop = FALSE]
      if (length(behaviours) != 5L || !setequal(behaviours,
          c("altruist", "egalitarian", "selfish", "antisocial", "inconsistent")) || nrow(matrix) != 16L) invalid()
      visible <- matrix[!matrix$suppressed, , drop = FALSE]
      if (nrow(visible) && (length(unique(visible$denominator_n)) != 1L ||
          sum(visible$count) > visible$denominator_n[[1L]] ||
          (nrow(visible) == 16L && sum(visible$count) != visible$denominator_n[[1L]]))) invalid()
    }
  }
  # Do not silently strip extra fields: reject them before any outbound request.
  tryCatch(assert_public_safe(results, secrets), error = function(error) invalid())
  if (v2 && !identical(metadata$content_fingerprint, public_content_fingerprint(results))) invalid()
  invisible(TRUE)
}

github_decode_results_file <- function(file, secrets = character(), allow_unpublished = FALSE) {
  if (!identical(file$type, "file") || !identical(file$path, "student/data/public_results.json") ||
      !identical(file$encoding, "base64") || !is.character(file$content) || length(file$content) != 1L ||
      is.na(file$content) || nchar(file$content, type = "bytes") > 14000000L) {
    stop("GitHub snapshot is not an aggregate JSON file.", call. = FALSE)
  }
  results <- tryCatch(suppressWarnings(jsonlite::fromJSON(
    rawToChar(jsonlite::base64_dec(file$content)), simplifyVector = TRUE
  )), error = function(error) NULL)
  validate_github_public_results(results, secrets = secrets, allow_unpublished = allow_unpublished)
  results
}

github_results_at_ref <- function(ref, target, token, request, allow_unpublished = FALSE) {
  file <- github_call(request, "GET", paste0(target$path,
    "/contents/student/data/public_results.json?ref=", utils::URLencode(ref, reserved = TRUE)), token)
  github_decode_results_file(file, secrets = token, allow_unpublished = allow_unpublished)
}

get_current_github_results <- function(config, token = Sys.getenv("GITHUB_PUBLICATION_TOKEN"),
                                        request = github_api_request) {
  target <- github_publication_target(config, token)
  github_results_at_ref(target$branch, target, token, request, allow_unpublished = TRUE)
}

pages_publication_base <- function(config) {
  repository <- config$publication$github_repository
  base <- config$publication$pages_base_url
  invalid <- function() stop("The student site must use the configured owner's HTTPS GitHub Pages address.", call. = FALSE)
  if (!github_scalar_text(repository) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*$", repository) ||
      !github_scalar_text(base, 1200L)) invalid()
  owner <- tolower(strsplit(repository, "/", fixed = TRUE)[[1L]][[1L]])
  if (!grepl("^https://[A-Za-z0-9-]+\\.github\\.io(/[A-Za-z0-9._~/-]*)?$", base)) invalid()
  address <- sub("^https://", "", base)
  host <- tolower(strsplit(address, "/", fixed = TRUE)[[1L]][[1L]])
  if (!identical(host, paste0(owner, ".github.io"))) invalid()
  path <- sub("^[^/]+", "", address)
  if (any(strsplit(path, "/", fixed = TRUE)[[1L]] %in% c(".", ".."))) invalid()
  sub("/+$", "", base)
}

# A deliberately separate, unauthenticated transport for the public student
# site. Never attach the GitHub or Qualtrics credentials or follow redirects.
# Injectable contract: (url) -> list(status = HTTP status, body = raw bytes).
pages_bytes_request <- function(url) {
  tryCatch(suppressWarnings({
    request <- httr2::request(url)
    request <- httr2::req_headers(request, Accept = "application/json", `Cache-Control` = "no-cache")
    request <- httr2::req_timeout(request, 12)
    request <- httr2::req_options(request, followlocation = FALSE)
    request <- httr2::req_error(request, is_error = function(response) FALSE)
    response <- httr2::req_perform(request)
    list(status = httr2::resp_status(response), body = httr2::resp_body_raw(response))
  }), error = function(error) stop("The published student snapshot could not be read.", call. = FALSE))
}

get_current_published_results <- function(config, request = pages_bytes_request, max_attempts = 3L,
                                          expected_manifest = NULL) {
  base <- pages_publication_base(config)
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L || !is.finite(max_attempts) ||
      max_attempts < 1 || max_attempts > 3 || max_attempts != as.integer(max_attempts)) {
    stop("Invalid student snapshot read limit.", call. = FALSE)
  }
  read_bytes <- function(path, maximum = 8 * 1024 * 1024) {
    response <- suppressWarnings(request(paste0(base, path)))
    if (!is.list(response) || !is.numeric(response$status) || length(response$status) != 1L ||
        is.na(response$status) || response$status != 200 ||
        !is.raw(response$body) || !length(response$body) || length(response$body) > maximum) stop("Invalid public response")
    response$body
  }
  decode <- function(bytes) {
    text <- rawToChar(bytes)
    if (anyNA(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA))) stop("Invalid UTF-8")
    jsonlite::fromJSON(text, simplifyVector = TRUE)
  }
  for (attempt in seq_len(max_attempts)) {
    results <- tryCatch(suppressWarnings({
      manifest <- decode(read_bytes(paste0("/data/public_manifest.json?cache=", as.integer(Sys.time())), 16384))
      fields <- c("schema_version", "publication_id", "generated_at_utc")
      if (!is.list(manifest) || !github_scalar_text(manifest$schema_version, 20L) ||
          !manifest$schema_version %in% c("1.0.0", "2.0.0")) stop("Invalid manifest")
      if (manifest$schema_version == "2.0.0") fields <- c(fields, "results_sha256")
      if (anyDuplicated(names(manifest)) || !setequal(names(manifest), fields) ||
          !github_scalar_text(manifest$publication_id, 120L) ||
          !grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", manifest$publication_id)) stop("Invalid manifest")
      # Deployment polling needs only the tiny manifest until the requested
      # publication appears. Compare every identity field and the expected
      # byte hash before downloading or validating a potentially old result.
      if (!is.null(expected_manifest) && (!is.list(expected_manifest) ||
          anyDuplicated(names(expected_manifest)) || !setequal(names(expected_manifest), fields) ||
          any(!vapply(fields, function(field) identical(manifest[[field]], expected_manifest[[field]]), logical(1))))) {
        stop("The requested publication is not yet available")
      }
      bytes <- read_bytes(paste0("/data/public_results.json?publication=", manifest$publication_id))
      if (manifest$schema_version == "2.0.0" &&
          !identical(manifest$results_sha256, unclass(as.character(openssl::sha256(bytes))))) stop("Snapshot checksum mismatch")
      candidate <- decode(bytes)
      validate_github_public_results(candidate, allow_unpublished = TRUE)
      for (field in c("schema_version", "publication_id", "generated_at_utc")) {
        if (!identical(candidate$metadata[[field]], manifest[[field]])) stop("Snapshot identity mismatch")
      }
      candidate
    }), error = function(error) NULL)
    if (!is.null(results)) return(results)
  }
  stop("The published student snapshot could not be verified; the previous verified snapshot is retained.", call. = FALSE)
}

verify_v2_deployment <- function(base_url, results, timeout_seconds = 180L, poll_seconds = 5L,
                                 request = pages_bytes_request) {
  if (!is.character(base_url) || length(base_url) != 1L || !nzchar(base_url)) return(FALSE)
  # Verify the same bytes students read, not only a newer manifest that may
  # briefly coexist with the previous results file during CDN propagation.
  owner <- sub("^https://([^./]+)\\.github\\.io.*$", "\\1", base_url)
  config <- list(publication = list(github_repository = paste0(owner, "/publication"), pages_base_url = base_url))
  expected <- public_manifest(results)
  deadline <- Sys.time() + as.numeric(timeout_seconds)
  while (Sys.time() < deadline) {
    published <- tryCatch(get_current_published_results(config, request = request, max_attempts = 1L,
      expected_manifest = expected), error = function(error) NULL)
    if (!is.null(published) && identical(published$metadata$schema_version, results$metadata$schema_version) &&
        identical(published$metadata$publication_id, results$metadata$publication_id) &&
        identical(published$metadata$generated_at_utc, results$metadata$generated_at_utc) &&
        identical(published$metadata$content_fingerprint, results$metadata$content_fingerprint)) return(TRUE)
    Sys.sleep(poll_seconds)
  }
  FALSE
}

publish_results_github <- function(results, config, secrets = character(),
                                   token = Sys.getenv("GITHUB_PUBLICATION_TOKEN"),
                                   verify = TRUE, request = github_api_request,
                                   before_commit = function() TRUE) {
  target <- github_publication_target(config, token)
  validate_github_public_results(results, secrets = c(secrets, token))
  v2 <- identical(results$metadata$schema_version, "2.0.0")
  authorize <- function() {
    allowed <- tryCatch(is.function(before_commit) && isTRUE(before_commit()), error = function(error) FALSE)
    if (!allowed) stop("Publication cancelled before the next GitHub write.", call. = FALSE)
  }
  outcome <- function(snapshot, commit_sha, changed, reconciled = FALSE) {
    deployment <- list(verified = FALSE, message = if (changed) {
      "Committed to GitHub; GitHub Actions will validate and deploy the site."
    } else "No data changes; the existing publication was retained.")
    if (isTRUE(verify)) {
      verified <- tryCatch(suppressWarnings(if (identical(snapshot$metadata$schema_version, "2.0.0")) {
        verify_v2_deployment(config$publication$pages_base_url %||% "", snapshot,
          config$publication$verify_timeout_seconds %||% 180L)
      } else isTRUE(verify_deployment(config$publication$pages_base_url %||% "",
        snapshot$metadata$publication_id, config$publication$verify_timeout_seconds %||% 180L)$verified)),
        error = function(error) FALSE)
      deployment <- list(verified = isTRUE(verified), message = if (isTRUE(verified)) {
        "GitHub Pages serves the requested publication."
      } else "Publication saved in GitHub; deployment is not yet confirmed. Check GitHub Actions.")
    }
    list(publication_id = snapshot$metadata$publication_id, commit_sha = commit_sha,
      commit_url = paste0("https://github.com/", target$repository, "/commit/", commit_sha),
      tests = "GitHub Actions validates the committed publication.",
      render = "GitHub Actions renders and scans the static site.", scanned_files = 2L,
      deployment = deployment, changed = changed, reconciled = reconciled,
      content_fingerprint = snapshot$metadata$content_fingerprint %||% public_content_fingerprint(snapshot),
      results = snapshot)
  }
  paths <- c("student/data/public_results.json", "student/data/public_manifest.json")
  serialised <- serialize_public_results(results)
  content <- list(serialised, as.character(jsonlite::toJSON(public_manifest(results, serialised),
    null = "null", auto_unbox = TRUE, pretty = TRUE)))
  reference_path <- paste0(target$path, "/git/ref/heads/", target$branch)
  head <- github_call(request, "GET", reference_path, token)
  if (!identical(head$object$type, "commit")) stop("GitHub branch does not point to a commit.", call. = FALSE)
  parent <- github_require_sha(head$object$sha)
  if (v2) {
    previous <- github_results_at_ref(parent, target, token, request, allow_unpublished = TRUE)
    if (identical(previous$metadata$content_fingerprint, results$metadata$content_fingerprint)) {
      return(outcome(previous, parent, changed = FALSE))
    }
  }
  base <- github_call(request, "GET", paste0(target$path, "/git/commits/", parent), token)
  base_tree <- github_require_sha(base$tree$sha)
  authorize()
  tree <- github_call(request, "POST", paste0(target$path, "/git/trees"), token,
    body = list(base_tree = base_tree, tree = lapply(seq_along(paths), function(i) {
      list(path = paths[[i]], mode = "100644", type = "blob", content = content[[i]])
    })), expected = 201L)
  tree_sha <- github_require_sha(tree$sha)
  commit <- github_call(request, "POST", paste0(target$path, "/git/commits"), token,
    body = list(message = paste("Publish classroom results", results$metadata$publication_id),
      tree = tree_sha, parents = list(parent)), expected = 201L)
  commit_sha <- github_require_sha(commit$sha)
  current <- github_call(request, "GET", reference_path, token)
  if (!identical(github_require_sha(current$object$sha), parent)) {
    stop("GitHub branch changed during publication; no branch update was attempted. Review and retry.", call. = FALSE)
  }
  authorize()
  updated <- tryCatch(github_call(request, "PATCH", paste0(target$path, "/git/refs/heads/", target$branch), token,
    body = list(sha = commit_sha, force = FALSE)), error = identity)
  if (inherits(updated, "error")) {
    if (v2) {
      # A lost PATCH response is not proof of failure. Reconcile by reading the
      # branch, never by retrying a write or forcing a reference update.
      reconciled <- tryCatch({
        remote <- github_call(request, "GET", reference_path, token)
        remote_sha <- github_require_sha(remote$object$sha)
        if (identical(remote_sha, commit_sha)) {
          outcome(results, commit_sha, changed = TRUE, reconciled = TRUE)
        } else {
          remote_results <- github_results_at_ref(remote_sha, target, token, request, allow_unpublished = TRUE)
          if (identical(remote_results$metadata$content_fingerprint, results$metadata$content_fingerprint)) {
            outcome(remote_results, remote_sha, changed = FALSE, reconciled = TRUE)
          } else NULL
        }
      }, error = function(error) NULL)
      if (!is.null(reconciled)) return(reconciled)
    }
    stop(updated)
  }
  if (!identical(github_require_sha(updated$object$sha), commit_sha)) {
    stop("GitHub did not confirm the requested commit; check publication state before retrying.", call. = FALSE)
  }
  outcome(results, commit_sha, changed = TRUE)
}

list_github_snapshots <- function(config, token = Sys.getenv("GITHUB_PUBLICATION_TOKEN"),
                                  request = github_api_request) {
  target <- github_publication_target(config, token)
  commits <- github_call(request, "GET", paste0(target$path,
    "/commits?path=student%2Fdata%2Fpublic_results.json&sha=",
    utils::URLencode(target$branch, reserved = TRUE), "&per_page=20"), token)
  empty <- data.frame(ref = character(), publication_id = character(), generated_at_utc = character(),
    label = character(), stringsAsFactors = FALSE)
  if (!length(commits)) return(empty)
  if (length(commits) > 20L) stop("GitHub returned an invalid snapshot list.", call. = FALSE)
  rows <- lapply(commits, function(commit) {
    sha <- github_require_sha(commit$sha)
    date <- commit$commit$committer$date
    if (!github_scalar_text(date, 40L) || !grepl("^[0-9T:+Z-]+$", date)) date <- ""
    message <- commit$commit$message
    id <- if (github_scalar_text(message, 160L) &&
      grepl("^Publish classroom results [A-Za-z0-9][A-Za-z0-9._-]*$", message) &&
      !grepl(token, message, fixed = TRUE)) sub("^Publish classroom results ", "", message) else ""
    data.frame(ref = sha, publication_id = id, generated_at_utc = date,
      label = trimws(paste(date, if (nzchar(id)) id else "Aggregate snapshot", substr(sha, 1L, 8L))),
      stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

read_github_snapshot <- function(ref, config, token = Sys.getenv("GITHUB_PUBLICATION_TOKEN"),
                                 request = github_api_request) {
  target <- github_publication_target(config, token)
  ref <- github_require_sha(ref)
  github_results_at_ref(ref, target, token, request)
}
