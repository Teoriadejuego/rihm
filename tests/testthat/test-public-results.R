testthat::test_that("public results contain no row-level identifiers or session code", {
  decisions <- binary_grid()
  class <- classify_preferences(decisions)
  reference <- classify_preferences(decisions)
  for (name in c("class", "reference")) {
    value <- get(name)
    value$gender_code <- rep(c(1, 2), length.out = nrow(value))
    value$country <- if (name == "class") "Spain" else rep(c("Spain", "Salvador"), length.out = nrow(value))
    value$session_code <- "SECRET-CLASS-CODE"
    assign(name, value)
  }
  results <- build_public_results(class, reference, minimum_cell_size = 5, publication_id = "test-publication")
  testthat::expect_silent(assert_public_safe(results, "SECRET-CLASS-CODE"))
  json <- jsonlite::toJSON(results, dataframe = "rows", na = "null", auto_unbox = TRUE)
  testthat::expect_false(grepl("SECRET-CLASS-CODE", json, fixed = TRUE))
  testthat::expect_false(grepl("session_code", json, fixed = TRUE))
})

testthat::test_that("forbidden public fields fail the privacy guard", {
  unsafe <- list(metadata = list(publication_id = "x"), session_password = "secret")
  testthat::expect_error(assert_public_safe(unsafe), "forbidden fields")
})

testthat::test_that("rollback creates a new publication while recording its source", {
  snapshot <- list(metadata = list(publication_id = "old", generated_at_utc = "old-time"))
  rolled_back <- prepare_rollback(snapshot)
  testthat::expect_false(identical(rolled_back$metadata$publication_id, "old"))
  testthat::expect_equal(rolled_back$metadata$rollback_of, "old")
})

