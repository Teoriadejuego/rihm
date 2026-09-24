github_test_results <- function() {
  cells <- data.frame(scope = "class", country = "Class", gender = "all",
    behaviour = c("altruist", "egalitarian", "selfish", "antisocial", "inconsistent"),
    count = c(60, 60, 40, 40, 40), denominator_n = c(160, 160, 160, 160, 200),
    percentage = c(37.5, 37.5, 25, 25, 20),
    denominator_type = c(rep("consistent", 4), "complete"), n_complete = 200,
    n_consistent = 160, suppressed = FALSE, stringsAsFactors = FALSE)
  matrix_cells <- expand.grid(scope = "class", country = "Class", gender = "all",
    compassion_level = 1:4, envy_level = 1:4, stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE)
  matrix_cells$count <- 10
  matrix_cells$denominator_n <- 160
  matrix_cells$percentage <- 6.2
  matrix_cells$suppressed <- FALSE
  list(metadata = list(schema_version = "1.0.0", publication_id = "test-20260924",
    generated_at_utc = "2026-09-24T12:00:00Z", source_snapshot_at_utc = "2026-09-24T11:59:00Z",
    minimum_cell_size = 5, classification_note = "Overlapping indicators."),
    cells = cells, matrix_cells = matrix_cells)
}

github_test_config <- function() list(publication = list(github_repository = "teacher/classroom", branch = "main"))
github_test_sha <- function(letter) paste(rep(letter, 40L), collapse = "")
github_test_response <- function(body, status = 200L) list(status = status, body = body)
github_test_ref <- function(letter) list(object = list(type = "commit", sha = github_test_sha(letter)))

github_test_transport <- function(responses) {
  calls <- list()
  list(request = function(method, path, token, body = NULL) {
    index <- length(calls) + 1L
    calls[[index]] <<- list(method = method, path = path, body = body)
    if (index > length(responses)) stop("Unexpected outbound request.")
    response <- responses[[index]]
    if (is.function(response)) response() else response
  }, calls = function() calls)
}

github_test_success_responses <- function() list(
  github_test_response(github_test_ref("a")),
  github_test_response(list(tree = list(sha = github_test_sha("b")))),
  github_test_response(list(sha = github_test_sha("c")), 201L),
  github_test_response(list(sha = github_test_sha("d")), 201L),
  github_test_response(github_test_ref("a")),
  github_test_response(github_test_ref("d"))
)

testthat::test_that("GitHub publishes exactly two aggregate files in one non-forced commit", {
  transport <- github_test_transport(github_test_success_responses())
  results <- github_test_results()
  output <- publish_results_github(results, github_test_config(), token = "test-token",
    verify = FALSE, request = transport$request)
  calls <- transport$calls()
  testthat::expect_identical(vapply(calls, `[[`, "", "method"), c("GET", "GET", "POST", "POST", "GET", "PATCH"))
  testthat::expect_identical(calls[[1L]]$path, "/repos/teacher/classroom/git/ref/heads/main")
  testthat::expect_identical(calls[[3L]]$body$base_tree, github_test_sha("b"))
  entries <- calls[[3L]]$body$tree
  testthat::expect_identical(vapply(entries, `[[`, "", "path"),
    c("student/data/public_results.json", "student/data/public_manifest.json"))
  testthat::expect_true(all(vapply(entries, function(entry) entry$mode == "100644" && entry$type == "blob", logical(1))))
  public <- jsonlite::fromJSON(entries[[1L]]$content)
  testthat::expect_identical(names(public), c("metadata", "cells", "matrix_cells"))
  testthat::expect_equal(public$cells, results$cells)
  testthat::expect_equal(jsonlite::fromJSON(entries[[2L]]$content), public_manifest(results))
  testthat::expect_identical(calls[[4L]]$body$parents, list(github_test_sha("a")))
  testthat::expect_identical(calls[[4L]]$body$tree, github_test_sha("c"))
  testthat::expect_identical(calls[[6L]]$body, list(sha = github_test_sha("d"), force = FALSE))
  testthat::expect_identical(output$commit_sha, github_test_sha("d"))
  testthat::expect_false(output$deployment$verified)
})

testthat::test_that("a branch race fails without a forced update or retry", {
  responses <- github_test_success_responses()
  responses[[5L]] <- github_test_response(github_test_ref("e"))
  transport <- github_test_transport(responses)
  testthat::expect_error(publish_results_github(github_test_results(), github_test_config(),
    token = "test-token", verify = FALSE, request = transport$request), "branch changed")
  testthat::expect_length(transport$calls(), 5L)
  for (status in c(409L, 422L)) {
    responses <- github_test_success_responses()
    responses[[6L]] <- github_test_response(list(message = "test-token SECRET-RESPONSE"), status)
    transport <- github_test_transport(responses)
    error <- tryCatch(publish_results_github(github_test_results(), github_test_config(),
      token = "test-token", verify = FALSE, request = transport$request), error = identity)
    testthat::expect_match(conditionMessage(error), "Nothing was force-updated or retried")
    testthat::expect_false(grepl("test-token|SECRET-RESPONSE", conditionMessage(error)))
    testthat::expect_length(transport$calls(), 6L)
  }
})

testthat::test_that("validation rejects secrets, extra fields, and exposed protected values before transport", {
  transport <- github_test_transport(list())
  invalid <- list()
  value <- github_test_results(); value$raw <- data.frame(answer = 1); invalid[[1L]] <- value
  value <- github_test_results(); value$cells$ResponseId <- "row-id"; invalid[[2L]] <- value
  value <- github_test_results(); value$metadata$classification_note <- "PRIVATE-CLASS-CODE"; invalid[[3L]] <- value
  value <- github_test_results(); value$cells$count[[1L]] <- 4; invalid[[4L]] <- value
  value <- github_test_results(); value$cells$suppressed[[1L]] <- TRUE; invalid[[5L]] <- value
  value <- github_test_results(); value$cells$count[[1L]] <- 0.5; invalid[[6L]] <- value
  for (value in invalid) {
    testthat::expect_error(publish_results_github(value, github_test_config(), secrets = "PRIVATE-CLASS-CODE",
      token = "test-token", verify = FALSE, request = transport$request), "protected aggregate")
  }
  testthat::expect_length(transport$calls(), 0L)
  valid <- github_test_results()
  valid$cells$suppressed[[1L]] <- TRUE
  for (field in c("count", "denominator_n", "percentage", "n_complete", "n_consistent")) valid$cells[[field]][[1L]] <- NA
  testthat::expect_silent(validate_github_public_results(valid))
})

testthat::test_that("invalid destinations and missing tokens never contact GitHub", {
  transport <- github_test_transport(list())
  testthat::expect_error(publish_results_github(github_test_results(), github_test_config(),
    token = "", verify = FALSE, request = transport$request), "TOKEN is missing")
  for (repository in c("../other", "https://github.com/a/b", "a/b/extra", "a/b?token=private")) {
    config <- github_test_config(); config$publication$github_repository <- repository
    testthat::expect_error(publish_results_github(github_test_results(), config,
      token = "test-token", verify = FALSE, request = transport$request), "owner/repository")
  }
  for (branch in c("../main", "main.lock", "main//other", "refs/heads/main", "main?x=1", "main\n")) {
    config <- github_test_config(); config$publication$branch <- branch
    testthat::expect_error(publish_results_github(github_test_results(), config,
      token = "test-token", verify = FALSE, request = transport$request), "branch is invalid")
  }
  testthat::expect_length(transport$calls(), 0L)
})

testthat::test_that("GitHub errors never include tokens, response bodies, or transport details", {
  for (response in list(
    github_test_response(list(message = "test-token PRIVATE-BODY"), 401L),
    function() stop("Authorization: test-token PRIVATE-BODY")
  )) {
    transport <- github_test_transport(list(response))
    error <- tryCatch(publish_results_github(github_test_results(), github_test_config(),
      token = "test-token", verify = FALSE, request = transport$request), error = identity)
    testthat::expect_match(conditionMessage(error), "GitHub request failed")
    testthat::expect_false(grepl("test-token|PRIVATE-BODY|Authorization", conditionMessage(error)))
    testthat::expect_length(transport$calls(), 1L)
  }
})

testthat::test_that("snapshot history and retrieval address only the aggregate JSON", {
  results <- github_test_results()
  json <- as.character(jsonlite::toJSON(results, dataframe = "rows", na = "null", auto_unbox = TRUE))
  transport <- github_test_transport(list(
    github_test_response(list(list(sha = github_test_sha("a"), commit = list(
      message = "Publish classroom results test-20260924", committer = list(date = "2026-09-24T12:00:00Z"))))),
    github_test_response(list(type = "file", path = "student/data/public_results.json", encoding = "base64",
      content = jsonlite::base64_enc(charToRaw(json))))
  ))
  snapshots <- list_github_snapshots(github_test_config(), token = "test-token", request = transport$request)
  testthat::expect_identical(names(snapshots), c("ref", "publication_id", "generated_at_utc", "label"))
  testthat::expect_identical(snapshots$ref, github_test_sha("a"))
  testthat::expect_identical(snapshots$publication_id, "test-20260924")
  restored <- read_github_snapshot(snapshots$ref[[1L]], github_test_config(),
    token = "test-token", request = transport$request)
  testthat::expect_equal(restored, results)
  calls <- transport$calls()
  testthat::expect_match(calls[[1L]]$path, "commits\\?path=student%2Fdata%2Fpublic_results.json&sha=main&per_page=20$")
  testthat::expect_identical(calls[[2L]]$path, paste0(
    "/repos/teacher/classroom/contents/student/data/public_results.json?ref=", github_test_sha("a")))
  empty <- github_test_transport(list(github_test_response(list())))
  testthat::expect_equal(nrow(list_github_snapshots(github_test_config(), token = "test-token", request = empty$request)), 0L)
})

testthat::test_that("snapshot retrieval rejects arbitrary paths and unsafe payloads", {
  transport <- github_test_transport(list())
  testthat::expect_error(read_github_snapshot("main?path=.Renviron", github_test_config(),
    token = "test-token", request = transport$request), "invalid object reference")
  testthat::expect_length(transport$calls(), 0L)
  for (payload in c('{"session_code":"PRIVATE-BODY"}', 'not json test-token PRIVATE-BODY')) {
    transport <- github_test_transport(list(github_test_response(list(type = "file",
      path = "student/data/public_results.json", encoding = "base64",
      content = jsonlite::base64_enc(charToRaw(payload))))))
    error <- tryCatch(read_github_snapshot(github_test_sha("a"), github_test_config(),
      token = "test-token", request = transport$request), error = identity)
    testthat::expect_match(conditionMessage(error), "protected aggregate")
    testthat::expect_false(grepl("test-token|PRIVATE-BODY", conditionMessage(error)))
  }
})
