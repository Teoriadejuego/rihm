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

validate_github_public_results <- function(results, secrets = character()) {
  invalid <- function() stop("Publication must contain only valid protected aggregate data.", call. = FALSE)
  exact_names <- function(value, expected) {
    !is.null(names(value)) && !anyDuplicated(names(value)) && setequal(names(value), expected)
  }
  if (!is.list(results) || !exact_names(results, c("metadata", "cells", "matrix_cells"))) invalid()
  metadata <- results$metadata
  required <- c("schema_version", "publication_id", "generated_at_utc", "source_snapshot_at_utc",
    "minimum_cell_size", "classification_note")
  optional <- c("rollback_of", "data_mode", "data_note")
  if (!is.list(metadata) || anyDuplicated(names(metadata)) ||
      !all(required %in% names(metadata)) || any(!names(metadata) %in% c(required, optional))) invalid()
  if (!identical(metadata$schema_version, "1.0.0")) invalid()
  for (name in setdiff(names(metadata), "minimum_cell_size")) {
    if (!github_scalar_text(metadata[[name]], if (name %in% c("classification_note", "data_note")) 1000L else 120L)) invalid()
  }
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", metadata$publication_id)) invalid()
  for (name in c("generated_at_utc", "source_snapshot_at_utc")) {
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", metadata[[name]])) invalid()
  }
  minimum <- metadata$minimum_cell_size
  if (!is.numeric(minimum) || length(minimum) != 1L || is.na(minimum) ||
      !is.finite(minimum) || minimum < 5L || minimum != floor(minimum)) invalid()
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
    dimensions <- setdiff(fields[[table]], c(numbers, "suppressed"))
    if (anyDuplicated(data[dimensions])) invalid()
  }
  # Do not silently strip extra fields: reject them before any outbound request.
  tryCatch(assert_public_safe(results, secrets), error = function(error) invalid())
  invisible(TRUE)
}

publish_results_github <- function(results, config, secrets = character(),
                                   token = Sys.getenv("GITHUB_PUBLICATION_TOKEN"),
                                   verify = TRUE, request = github_api_request) {
  target <- github_publication_target(config, token)
  validate_github_public_results(results, secrets = c(secrets, token))
  paths <- c("student/data/public_results.json", "student/data/public_manifest.json")
  payloads <- list(results, public_manifest(results))
  content <- lapply(payloads, function(value) as.character(jsonlite::toJSON(
    value, dataframe = "rows", na = "null", auto_unbox = TRUE, pretty = TRUE
  )))
  reference_path <- paste0(target$path, "/git/ref/heads/", target$branch)
  head <- github_call(request, "GET", reference_path, token)
  if (!identical(head$object$type, "commit")) stop("GitHub branch does not point to a commit.", call. = FALSE)
  parent <- github_require_sha(head$object$sha)
  base <- github_call(request, "GET", paste0(target$path, "/git/commits/", parent), token)
  base_tree <- github_require_sha(base$tree$sha)
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
  updated <- github_call(request, "PATCH", paste0(target$path, "/git/refs/heads/", target$branch), token,
    body = list(sha = commit_sha, force = FALSE))
  if (!identical(github_require_sha(updated$object$sha), commit_sha)) {
    stop("GitHub did not confirm the requested commit; check publication state before retrying.", call. = FALSE)
  }
  deployment <- list(verified = FALSE, message = "Committed to GitHub; GitHub Actions will validate and deploy the site.")
  if (isTRUE(verify)) {
    checked <- tryCatch(suppressWarnings(verify_deployment(
      config$publication$pages_base_url %||% "", results$metadata$publication_id,
      config$publication$verify_timeout_seconds %||% 180L
    )), error = function(error) NULL)
    deployment <- if (!is.null(checked) && isTRUE(checked$verified)) {
      list(verified = TRUE, message = "GitHub Pages serves the requested publication.")
    } else list(verified = FALSE, message = "Committed to GitHub; deployment is not yet confirmed. Check GitHub Actions.")
  }
  list(publication_id = results$metadata$publication_id, commit_sha = commit_sha,
    commit_url = paste0("https://github.com/", target$repository, "/commit/", commit_sha),
    tests = "GitHub Actions validates the committed publication.",
    render = "GitHub Actions renders and scans the static site.",
    scanned_files = 2L, deployment = deployment)
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
  file <- github_call(request, "GET", paste0(target$path,
    "/contents/student/data/public_results.json?ref=", ref), token)
  if (!identical(file$type, "file") || !identical(file$path, "student/data/public_results.json") ||
      !identical(file$encoding, "base64") || !is.character(file$content) || length(file$content) != 1L ||
      is.na(file$content) || nchar(file$content, type = "bytes") > 14000000L) {
    stop("GitHub snapshot is not an aggregate JSON file.", call. = FALSE)
  }
  results <- tryCatch(suppressWarnings(jsonlite::fromJSON(
    rawToChar(jsonlite::base64_dec(file$content)), simplifyVector = TRUE
  )), error = function(error) NULL)
  validate_github_public_results(results, secrets = token)
  results
}
