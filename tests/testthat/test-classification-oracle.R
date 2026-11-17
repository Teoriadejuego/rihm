testthat::test_that("every binary pattern matches the fixed independent category oracle", {
  expected <- utils::read.csv(testthat::test_path("..", "fixtures", "classification-oracle.csv"),
    na.strings = "", check.names = FALSE)
  observed <- classify_preferences(expected[decision_columns])
  testthat::expect_equal(nrow(expected), 64L)
  testthat::expect_equal(nrow(unique(expected[decision_columns])), 64L)
  for (column in setdiff(names(expected), decision_columns)) {
    testthat::expect_equal(observed[[column]], expected[[column]], info = column)
  }
})
