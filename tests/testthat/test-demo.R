demo_config <- function() {
  temporary <- tempfile("demo-project-")
  dir.create(file.path(temporary, "config"), recursive = TRUE)
  locations <- data.frame(
    uni = c(4, 26, 21, 14, 29, 18),
    country = c("Dominican Republic", "Ivory Coast", "Madagascar", "Philippines", "Salvador", "Spain")
  )
  locations_file <- file.path(temporary, "config", "reference_locations.csv")
  utils::write.csv(locations, locations_file, row.names = FALSE)
  list(
    project_root = temporary,
    locations_file = locations_file,
    qualtrics = list(session_code_column = "session_password"),
    privacy = list(minimum_cell_size = 5L)
  )
}

testthat::test_that("the demonstration uses both survey schemas and exercises private diagnostics", {
  candidate <- prepare_demo_candidate(demo_config(), " demo-rihm ")
  testthat::expect_identical(candidate$class$schema, "dic_pairs")
  testthat::expect_identical(candidate$reference$schema, "DIC")
  for (scope in c("class", "reference")) {
    diagnostics <- candidate[[scope]]$diagnostics
    testthat::expect_true(all(diagnostics$value > 0))
    testthat::expect_equal(diagnostics$value[diagnostics$metric == "Duplicate ResponseIds removed"], 1)
    testthat::expect_true(all(c(1, 2) %in% candidate[[scope]]$data$gender_code))
  }
  testthat::expect_equal(length(unique(candidate$reference$data$country)), 6L)
})

testthat::test_that("the demonstration is labelled and the ordinary privacy contract is retained", {
  candidate <- prepare_demo_candidate(demo_config())
  results <- candidate$results
  testthat::expect_identical(results$metadata$data_mode, "demonstration")
  testthat::expect_match(results$metadata$data_note, "Synthetic.*no real participants")
  testthat::expect_match(results$metadata$publication_id, "^demo-")
  testthat::expect_identical(results$metadata$schema_version, "1.0.0")
  testthat::expect_silent(assert_public_safe(results, demo_session_code()))
  json <- jsonlite::toJSON(results, dataframe = "rows", na = "null", auto_unbox = TRUE)
  testthat::expect_false(grepl(demo_session_code(), json, fixed = TRUE))
  testthat::expect_false(grepl("synthetic-class-", json, fixed = TRUE))
  testthat::expect_false(grepl("synthetic-reference-", json, fixed = TRUE))
  for (table in c("cells", "matrix_cells")) {
    visible <- results[[table]][!results[[table]]$suppressed, ]
    testthat::expect_true(all(visible$count >= 5))
    testthat::expect_true(all(visible$denominator_n - visible$count >= 5))
  }
})

testthat::test_that("country and gender filters display varied complete demonstration matrices", {
  first <- prepare_demo_candidate(demo_config())
  second <- prepare_demo_candidate(demo_config())
  testthat::expect_equal(first$results$cells, second$results$cells)
  testthat::expect_equal(first$results$matrix_cells, second$results$matrix_cells)
  testthat::expect_false(identical(first$results$metadata$publication_id, second$results$metadata$publication_id))
  matrix <- first$results$matrix_cells
  testthat::expect_false(any(matrix$suppressed))
  testthat::expect_equal(nrow(matrix), 384L)
  cells <- first$results$cells
  testthat::expect_equal(nrow(cells), 120L)
  for (behaviour in c("altruist", "egalitarian", "selfish", "antisocial", "inconsistent")) {
    country <- cells[cells$scope == "international" & cells$gender == "all" & cells$behaviour == behaviour, ]
    testthat::expect_gt(length(unique(country$percentage)), 1L)
  }
  class <- cells[cells$scope == "class" & cells$behaviour == "altruist" & cells$gender != "all", ]
  testthat::expect_equal(length(unique(class$percentage)), 2L)
})

testthat::test_that("a different code cannot select the demonstration", {
  config <- demo_config()
  for (code in list("CLASS-1", "", NA_character_, character())) {
    testthat::expect_error(prepare_demo_candidate(config, code), "demonstration code")
  }
})
