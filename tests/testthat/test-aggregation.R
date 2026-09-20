testthat::test_that("behaviour and inconsistent denominators are explicit", {
  decisions <- binary_grid()
  data <- classify_preferences(decisions)
  data$scope <- "class"
  data$country <- "Spain"
  data$gender_code <- rep(c(1, 2), length.out = nrow(data))
  cells <- aggregate_behaviour_cells(data, "class")
  all_cells <- cells[cells$gender == "all", ]
  testthat::expect_true(all(all_cells$denominator_n[all_cells$behaviour != "inconsistent"] == 16))
  testthat::expect_equal(all_cells$denominator_n[all_cells$behaviour == "inconsistent"], 64)
  testthat::expect_equal(all_cells$count[all_cells$behaviour == "inconsistent"], 48)
})

testthat::test_that("primary suppression protects small counts and complements", {
  data <- data.frame(
    count = c(4, 5, 6), denominator_n = c(10, 10, 10),
    percentage = c(40, 50, 60), suppressed = FALSE
  )
  output <- apply_primary_suppression(data, 5)
  testthat::expect_equal(output$suppressed, c(TRUE, FALSE, TRUE))
})

testthat::test_that("secondary suppression leaves at least two unknown gender cells", {
  data <- data.frame(
    scope = "class", country = "Class", gender = c("all", "female", "male"),
    behaviour = "altruist", denominator_type = "consistent",
    count = c(10, 4, 6), denominator_n = c(20, 8, 12),
    percentage = c(50, 50, 50), n_complete = c(20, 8, 12),
    n_consistent = c(20, 8, 12), suppressed = c(FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  output <- apply_secondary_suppression(data, c("gender", "country"))
  testthat::expect_gte(sum(output$suppressed), 2)
})

testthat::test_that("redaction removes every numeric value from suppressed cells", {
  data <- data.frame(
    count = c(4, 6), denominator_n = c(10, 10), percentage = c(40, 60),
    n_complete = c(10, 10), n_consistent = c(8, 8), suppressed = c(TRUE, FALSE)
  )
  output <- redact_suppressed(data)
  testthat::expect_true(all(is.na(output[1, 1:5])))
  testthat::expect_false(any(is.na(output[2, 1:5])))
})

testthat::test_that("one hidden matrix category forces a second hidden category", {
  data <- expand.grid(
    scope = "class", country = "Class", gender = "all",
    compassion_level = 1:4, envy_level = 1:4,
    stringsAsFactors = FALSE
  )
  data$count <- seq_len(16)
  data$denominator_n <- 136
  data$percentage <- 100 * data$count / data$denominator_n
  data$suppressed <- c(TRUE, rep(FALSE, 15))
  output <- apply_matrix_complement_suppression(data)
  testthat::expect_equal(sum(output$suppressed), 2)
})

testthat::test_that("a hidden inconsistent count cannot be inferred from public totals", {
  data <- data.frame(
    scope = "class", country = "Class", gender = "all",
    behaviour = names(public_behaviours),
    count = c(10, 10, 10, 10, 2), denominator_n = c(18, 18, 18, 18, 20),
    percentage = c(55.6, 55.6, 55.6, 55.6, 10),
    denominator_type = c(rep("consistent", 4), "complete"),
    n_complete = 20, n_consistent = 18,
    suppressed = c(FALSE, FALSE, FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  output <- protect_inconsistent_totals(data)
  testthat::expect_true(all(is.na(output$n_complete)))
  testthat::expect_true(all(output$n_consistent == 18))
})
