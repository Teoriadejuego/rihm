v2_test_results <- function() {
  cells <- data.frame(scope = "class", country = "Class", gender = "all",
    behaviour = c("altruist", "egalitarian", "selfish", "antisocial", "inconsistent"),
    count = c(60, 60, 40, 40, 40), denominator_n = c(160, 160, 160, 160, 200),
    percentage = c(37.5, 37.5, 25, 25, 20),
    denominator_type = c(rep("consistent", 4), "complete"), n_complete = 200,
    n_consistent = 160, suppressed = FALSE, stringsAsFactors = FALSE)
  matrix <- expand.grid(scope = "class", country = "Class", gender = "all",
    compassion_level = 1:4, envy_level = 1:4, stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE)
  matrix$count <- 10; matrix$denominator_n <- 160; matrix$percentage <- 6.2; matrix$suppressed <- FALSE
  results <- list(metadata = list(schema_version = "2.0.0", publication_id = "new-publication",
    generated_at_utc = "2026-11-17T12:00:00Z", source_snapshot_at_utc = "2026-11-17T11:59:00Z",
    minimum_cell_size = 5L, classification_note = "Overlapping indicators.",
    window_start_utc = "2001-01-01T11:00:00Z", window_end_utc = "2001-01-01T12:00:00Z",
    selection_rule = "latest_response_hour", class_source_at_utc = "2026-11-17T11:59:00Z",
    reference_source_at_utc = "2026-11-17T11:58:00Z", classification_version = "1.0.0",
    privacy_version = "1.0.0", data_mode = "qualtrics"), cells = cells, matrix_cells = matrix)
  results$metadata$content_fingerprint <- public_content_fingerprint(results)
  results
}

v2_test_config <- function() list(publication = list(github_repository = "teacher/classroom", branch = "main"))
v2_sha <- function(value) paste(rep(value, 40), collapse = "")
v2_response <- function(body, status = 200L) list(status = status, body = body)
v2_reference <- function(value) v2_response(list(object = list(type = "commit", sha = v2_sha(value))))
v2_file <- function(results) v2_response(list(type = "file", path = "student/data/public_results.json",
  encoding = "base64", content = jsonlite::base64_enc(charToRaw(serialize_public_results(results)))))
v2_transport <- function(responses) {
  calls <- list()
  list(request = function(method, path, token, body = NULL) {
    i <- length(calls) + 1L
    calls[[i]] <<- list(method = method, path = path, body = body)
    if (i > length(responses)) stop("Unexpected request")
    if (is.function(responses[[i]])) responses[[i]]() else responses[[i]]
  }, calls = function() calls)
}
v2_previous <- function() {
  previous <- v2_test_results()
  previous$metadata$publication_id <- "previous-publication"
  previous$metadata$window_start_utc <- "2000-01-01T11:00:00Z"
  previous$metadata$window_end_utc <- "2000-01-01T12:00:00Z"
  previous$metadata$content_fingerprint <- public_content_fingerprint(previous)
  previous
}
v2_success <- function() list(v2_reference("a"), v2_file(v2_previous()),
  v2_response(list(tree = list(sha = v2_sha("b")))), v2_response(list(sha = v2_sha("c")), 201L),
  v2_response(list(sha = v2_sha("d")), 201L), v2_reference("a"), v2_reference("d"))

pages_test_config <- function() list(publication = list(github_repository = "teacher/classroom",
  pages_base_url = "https://teacher.github.io/classroom/"))
pages_test_pair <- function(results = v2_test_results()) {
  text <- serialize_public_results(results)
  list(manifest = charToRaw(as.character(jsonlite::toJSON(public_manifest(results, text),
    null = "null", auto_unbox = TRUE))), results = charToRaw(text))
}
pages_test_transport <- function(responses) {
  calls <- character()
  list(request = function(url) {
    calls <<- c(calls, url)
    value <- responses[[length(calls)]]
    if (is.function(value)) value() else list(status = 200L, body = value)
  }, calls = function() calls)
}

testthat::test_that("teacher restoration uses the verified Pages bytes, without credentials or repository HEAD", {
  pair <- pages_test_pair()
  transport <- pages_test_transport(pair)
  actual <- get_current_published_results(pages_test_config(), request = transport$request)
  testthat::expect_equal(actual, v2_test_results())
  testthat::expect_length(transport$calls(), 2L)
  testthat::expect_match(transport$calls()[[1L]], "^https://teacher.github.io/classroom/data/public_manifest.json[?]cache=[0-9]+$")
  testthat::expect_identical(transport$calls()[[2L]],
    "https://teacher.github.io/classroom/data/public_results.json?publication=new-publication")
})

testthat::test_that("teacher restoration verifies exact bytes and retries mixed CDN publication pairs", {
  next_pair <- pages_test_pair()
  previous_pair <- pages_test_pair(v2_previous())
  transport <- pages_test_transport(list(next_pair$manifest, previous_pair$results,
    next_pair$manifest, next_pair$results))
  testthat::expect_identical(get_current_published_results(pages_test_config(), request = transport$request)$metadata$publication_id,
    "new-publication")
  testthat::expect_length(transport$calls(), 4L)
  altered <- c(next_pair$results, charToRaw("\n"))
  transport <- pages_test_transport(rep(list(next_pair$manifest, altered), 3L))
  testthat::expect_error(get_current_published_results(pages_test_config(), request = transport$request),
    "previous verified snapshot is retained")
  testthat::expect_length(transport$calls(), 6L)
})

testthat::test_that("teacher restoration supports the explicit legacy bootstrap and published v1 contract", {
  legacy <- v2_test_results()
  legacy$metadata <- legacy$metadata[c("schema_version", "publication_id", "generated_at_utc",
    "source_snapshot_at_utc", "minimum_cell_size", "classification_note")]
  legacy$metadata$schema_version <- "1.0.0"
  transport <- pages_test_transport(pages_test_pair(legacy))
  testthat::expect_equal(get_current_published_results(pages_test_config(), request = transport$request), legacy)
  bootstrap <- legacy
  bootstrap$metadata$publication_id <- "not-published"
  bootstrap$metadata[c("generated_at_utc", "source_snapshot_at_utc")] <- list(NULL, NULL)
  bootstrap$cells <- list(); bootstrap$matrix_cells <- list()
  transport <- pages_test_transport(pages_test_pair(bootstrap))
  testthat::expect_equal(get_current_published_results(pages_test_config(), request = transport$request), bootstrap)
})

testthat::test_that("teacher restoration rejects untrusted URLs before making any request", {
  called <- FALSE
  request <- function(url) { called <<- TRUE; stop("must not run") }
  for (url in c("http://teacher.github.io/classroom", "https://teacher.github.io.evil.test/classroom",
    "https://other.github.io/classroom", "https://teacher.github.io@evil.test/classroom",
    "https://teacher.github.io/classroom?token=secret", "https://teacher.github.io/../private",
    "https://teacher.github.io/%2e%2e/private", "https://teacher.github.io:443/classroom")) {
    config <- pages_test_config(); config$publication$pages_base_url <- url
    testthat::expect_error(get_current_published_results(config, request = request), "HTTPS GitHub Pages")
  }
  testthat::expect_false(called)
})

testthat::test_that("teacher restoration rejects invalid identities, manifests and unsafe aggregate data", {
  pair <- pages_test_pair()
  bad <- v2_test_results(); bad$cells$count[[1L]] <- 1L
  bad$metadata$content_fingerprint <- public_content_fingerprint(bad)
  wrong_manifest <- public_manifest(v2_test_results())
  wrong_manifest$publication_id <- "another-publication"
  extra_manifest <- public_manifest(v2_test_results()); extra_manifest$private_key <- "test-sensitive-marker"
  for (candidate in list(pages_test_pair(bad),
    list(charToRaw(as.character(jsonlite::toJSON(wrong_manifest, auto_unbox = TRUE))), pair$results),
    list(charToRaw(as.character(jsonlite::toJSON(extra_manifest, auto_unbox = TRUE))), pair$results))) {
    transport <- pages_test_transport(candidate)
    testthat::expect_error(get_current_published_results(pages_test_config(), request = transport$request,
      max_attempts = 1L), "could not be verified")
  }
  transport <- pages_test_transport(list(function() stop("test-sensitive-marker")))
  error <- tryCatch(get_current_published_results(pages_test_config(), request = transport$request,
    max_attempts = 1L), error = conditionMessage)
  testthat::expect_false(grepl("test-sensitive-marker", error, fixed = TRUE))
})

testthat::test_that("semantic fingerprints ignore operational identity but include scientific content and window", {
  results <- v2_test_results()
  reordered <- results
  reordered$metadata$publication_id <- "different-id"
  for (field in c("generated_at_utc", "source_snapshot_at_utc", "class_source_at_utc", "reference_source_at_utc")) {
    reordered$metadata[[field]] <- "2026-11-18T12:00:00Z"
  }
  reordered$cells <- reordered$cells[5:1, rev(names(reordered$cells))]
  reordered$matrix_cells <- reordered$matrix_cells[16:1, rev(names(reordered$matrix_cells))]
  testthat::expect_identical(public_content_fingerprint(reordered), results$metadata$content_fingerprint)
  for (field in c("window_end_utc", "privacy_version", "classification_version", "data_mode")) {
    changed <- results; changed$metadata[[field]] <- "different"
    testthat::expect_false(identical(public_content_fingerprint(changed), results$metadata$content_fingerprint))
  }
  changed <- results; changed$cells$count[[1L]] <- 61
  testthat::expect_false(identical(public_content_fingerprint(changed), results$metadata$content_fingerprint))
})

testthat::test_that("v2 manifests hash the exact UTF-8 output bytes written to disk", {
  results <- v2_test_results()
  results$metadata$classification_note <- "Overlapping indicators — considérations."
  results$metadata$content_fingerprint <- public_content_fingerprint(results)
  text <- serialize_public_results(results)
  manifest <- public_manifest(results, text)
  root <- tempfile("v2-bytes-"); dir.create(root)
  written <- write_public_snapshot(results, root, save_snapshot = FALSE)
  bytes <- readBin(written$data, "raw", file.info(written$data)$size)
  testthat::expect_identical(bytes, charToRaw(enc2utf8(text)))
  testthat::expect_identical(manifest$results_sha256, unclass(as.character(openssl::sha256(bytes))))
  testthat::expect_identical(jsonlite::read_json(written$manifest)$results_sha256, manifest$results_sha256)
  testthat::expect_false(identical(sha256_utf8(paste0(text, "\n")), manifest$results_sha256))
  testthat::expect_identical(serialize_public_results(jsonlite::fromJSON(text)), text)
})

testthat::test_that("v2 validation rejects invalid dates, windows, hashes and exposed protected counts", {
  testthat::expect_silent(validate_github_public_results(v2_test_results()))
  invalid <- list()
  value <- v2_test_results(); value$metadata$generated_at_utc <- "2026-02-30T12:00:00Z"; invalid[[1L]] <- value
  value <- v2_test_results(); value$metadata$window_start_utc <- "2001-01-01T10:00:00Z"; invalid[[2L]] <- value
  value <- v2_test_results(); value$metadata$unexpected <- "not permitted"; invalid[[3L]] <- value
  value <- v2_test_results(); value$metadata$content_fingerprint <- strrep("a", 64); invalid[[4L]] <- value
  value <- v2_test_results(); value$cells$suppressed[[1L]] <- TRUE; invalid[[5L]] <- value
  value <- v2_test_results(); value$cells$count[[1L]] <- 4; invalid[[6L]] <- value
  value <- v2_test_results(); value$matrix_cells <- value$matrix_cells[-1L, ]; invalid[[7L]] <- value
  value <- v2_test_results(); value$cells <- list(); value$matrix_cells <- list(); invalid[[8L]] <- value
  for (value in invalid) testthat::expect_error(validate_github_public_results(value), "protected aggregate")
})

testthat::test_that("identical v2 content keeps the existing publication and makes no writes", {
  current <- v2_test_results(); current$metadata$publication_id <- "already-published"
  transport <- v2_transport(list(v2_reference("a"), v2_file(current)))
  output <- publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
    verify = FALSE, request = transport$request)
  testthat::expect_false(output$changed)
  testthat::expect_identical(output$publication_id, "already-published")
  testthat::expect_identical(output$results$metadata$publication_id, "already-published")
  testthat::expect_identical(vapply(transport$calls(), `[[`, "", "method"), c("GET", "GET"))
})

testthat::test_that("v2 publication puts an exact manifest beside results and checks cancellation before writes", {
  transport <- v2_transport(v2_success())
  checks <- 0L
  published <- publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
    verify = FALSE, request = transport$request, before_commit = function() { checks <<- checks + 1L; TRUE })
  testthat::expect_true(published$changed)
  testthat::expect_equal(checks, 2L)
  entries <- transport$calls()[[4L]]$body$tree
  testthat::expect_identical(jsonlite::fromJSON(entries[[2L]]$content)$results_sha256, sha256_utf8(entries[[1L]]$content))
  for (allowed_checks in 0:1) {
    transport <- v2_transport(v2_success()); checks <- 0L
    testthat::expect_error(publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
      verify = FALSE, request = transport$request,
      before_commit = function() { checks <<- checks + 1L; checks <= allowed_checks }), "cancelled")
    testthat::expect_false(any(vapply(transport$calls(), `[[`, "", "method") == "PATCH"))
    if (!allowed_checks) testthat::expect_false(any(vapply(transport$calls(), `[[`, "", "method") == "POST"))
  }
})

testthat::test_that("a lost PATCH response is reconciled read-only without duplicate publication", {
  responses <- v2_success()
  responses[[7L]] <- function() stop("private transport failure")
  responses[[8L]] <- v2_reference("d")
  transport <- v2_transport(responses)
  output <- publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
    verify = FALSE, request = transport$request)
  testthat::expect_true(output$reconciled)
  testthat::expect_true(output$changed)
  testthat::expect_equal(sum(vapply(transport$calls(), `[[`, "", "method") == "PATCH"), 1L)
  responses[[8L]] <- v2_reference("e")
  responses[[9L]] <- v2_file(v2_previous())
  transport <- v2_transport(responses)
  testthat::expect_error(publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
    verify = FALSE, request = transport$request), "GitHub request failed")
  testthat::expect_equal(sum(vapply(transport$calls(), `[[`, "", "method") == "PATCH"), 1L)
})

testthat::test_that("current GitHub results are read at the configured branch with the strict contract", {
  transport <- v2_transport(list(v2_file(v2_test_results())))
  current <- get_current_github_results(v2_test_config(), token = "test-token", request = transport$request)
  testthat::expect_identical(current$metadata$content_fingerprint, v2_test_results()$metadata$content_fingerprint)
  testthat::expect_match(transport$calls()[[1L]]$path, "public_results.json[?]ref=main$")
})

testthat::test_that("the narrowly defined v1 bootstrap can be read but cannot be republished", {
  baseline <- list(metadata = list(schema_version = "1.0.0", publication_id = "not-published",
    generated_at_utc = NULL, source_snapshot_at_utc = NULL, minimum_cell_size = 5,
    classification_note = "Overlapping indicators."), cells = list(), matrix_cells = list())
  testthat::expect_silent(validate_github_public_results(baseline, allow_unpublished = TRUE))
  testthat::expect_error(validate_github_public_results(baseline), "protected aggregate")
  transport <- v2_transport(list(v2_file(baseline)))
  current <- get_current_github_results(v2_test_config(), token = "test-token", request = transport$request)
  testthat::expect_identical(current$metadata$publication_id, "not-published")
  testthat::expect_null(current$metadata$generated_at_utc)
  malformed <- baseline; malformed$metadata$publication_id <- "another-empty-snapshot"
  testthat::expect_error(validate_github_public_results(malformed, allow_unpublished = TRUE), "protected aggregate")
  responses <- v2_success(); responses[[2L]] <- v2_file(baseline)
  transport <- v2_transport(responses)
  testthat::expect_true(publish_results_github(v2_test_results(), v2_test_config(), token = "test-token",
    verify = FALSE, request = transport$request)$changed)
})
