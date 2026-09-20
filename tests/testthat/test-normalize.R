testthat::test_that("both known Qualtrics schemas normalise to the same decisions", {
  decisions <- binary_grid()[1:8, ]
  classic <- normalise_survey(make_raw_dic(decisions), "class", test_locations())
  paired <- normalise_survey(make_raw_pairs(decisions), "class", test_locations())
  testthat::expect_equal(classic[decision_columns], decisions)
  testthat::expect_equal(paired[decision_columns], decisions)
  testthat::expect_equal(unique(classic$source_schema), "DIC")
  testthat::expect_equal(unique(paired$source_schema), "dic_pairs")
})

testthat::test_that("paired columns coalesce and missing columns fail clearly", {
  decisions <- binary_grid()[1:2, ]
  raw <- make_raw_pairs(decisions)
  raw$dic10_6_2 <- raw$dic10_6
  raw$dic10_6[[1]] <- NA
  output <- normalise_survey(raw, "class", test_locations())
  testthat::expect_equal(output$DP1, decisions$DP1)

  raw$dic11_19 <- NULL
  testthat::expect_error(normalise_survey(raw, "class", test_locations()), "Missing required decision column")
})

testthat::test_that("class session matching is case insensitive and mandatory", {
  data <- normalise_survey(make_raw_dic(binary_grid()[1:3, ], session = "AbC"), "class", test_locations())
  testthat::expect_equal(nrow(filter_class_session(data, "abc")), 3)
  testthat::expect_error(filter_class_session(data, "missing"), "No class responses")
  testthat::expect_error(filter_class_session(data, ""), "required")
})

testthat::test_that("duplicate ResponseIds keep the latest response", {
  data <- normalise_survey(make_raw_dic(binary_grid()[1:3, ]), "class", test_locations())
  data$response_id[2] <- data$response_id[1]
  data$end_date[1:2] <- c("2026-01-01 10:00:00", "2026-01-01 11:00:00")
  result <- deduplicate_responses(data)
  testthat::expect_equal(result$duplicate_count, 1)
  testthat::expect_true(2 %in% result$data$row_index)
})

