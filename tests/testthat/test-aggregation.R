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

counted_patterns <- function(compassion, envy, counts, country = "Spain", inconsistent = 0L) {
  patterns <- classify_preferences(binary_grid())
  indexes <- vapply(seq_along(counts), function(i) {
    which(patterns$consistent & patterns$compassionincreas == compassion[[i]] &
            patterns$envyincreas == envy[[i]])[[1L]]
  }, integer(1))
  rows <- rep(indexes, counts)
  if (inconsistent > 0L) rows <- c(rows, rep(which(!patterns$consistent)[[1L]], inconsistent))
  data <- patterns[rows, ]
  data$gender_code <- rep(c(1, 2), length.out = nrow(data))
  data$country <- country
  data
}

testthat::test_that("98 altruist and 98 egalitarian cannot reveal four antisocial responses", {
  data <- counted_patterns(c(4, 4, 1), c(1, 4, 1), c(98, 98, 4))
  public <- aggregate_public_data(data, data)
  cells <- public$cells[public$cells$scope == "class" & public$cells$gender == "all", ]
  antisocial <- cells[cells$behaviour == "antisocial", ]
  others <- cells[cells$behaviour %in% c("altruist", "egalitarian"), ]
  testthat::expect_true(antisocial$suppressed)
  testthat::expect_true(is.na(antisocial$count))
  testthat::expect_true(any(others$suppressed))
  testthat::expect_true(any(!others$suppressed))
  # A withheld behaviour must not be reconstructed from its matrix region.
  for (behaviour in others$behaviour[others$suppressed]) {
    matrix <- public$matrix_cells[public$matrix_cells$scope == "class" &
      public$matrix_cells$gender == "all" & public$matrix_cells$compassion_level >= 2, ]
    matrix <- matrix[if (behaviour == "altruist") matrix$envy_level <= 2 else matrix$envy_level >= 3, ]
    testthat::expect_true(any(matrix$suppressed))
  }
})

testthat::test_that("a behaviour total cannot reveal a protected matrix component", {
  grid <- expand.grid(compassion = 1:4, envy = 1:4)
  counts <- rep(20L, nrow(grid))
  counts[grid$compassion == 3 & grid$envy == 1] <- 4L
  data <- counted_patterns(grid$compassion, grid$envy, counts, inconsistent = 20L)
  public <- aggregate_public_data(data, data)
  altruist <- public$cells[public$cells$scope == "class" & public$cells$gender == "all" &
    public$cells$behaviour == "altruist", ]
  components <- public$matrix_cells[public$matrix_cells$scope == "class" &
    public$matrix_cells$gender == "all" & public$matrix_cells$compassion_level >= 2 &
    public$matrix_cells$envy_level <= 2, ]
  protected <- components[components$compassion_level == 3 & components$envy_level == 1, ]
  testthat::expect_true(protected$suppressed)
  testthat::expect_true(altruist$suppressed || sum(components$suppressed) >= 2L)
  testthat::expect_true(any(!public$matrix_cells$suppressed))
})

testthat::test_that("safe dense tables retain all behaviour and matrix cells", {
  grid <- expand.grid(compassion = 1:4, envy = 1:4)
  data <- counted_patterns(grid$compassion, grid$envy, rep(20L, 16), inconsistent = 20L)
  public <- aggregate_public_data(data, data)
  testthat::expect_false(any(public$cells$suppressed))
  testthat::expect_false(any(public$matrix_cells$suppressed))
})

testthat::test_that("gender totals cannot expose a small behaviour through another gender", {
  set.seed(18)
  data <- classify_preferences(binary_grid()[sample(1:64, 160, replace = TRUE), ])
  data$gender_code <- rep(c(1, 2), 80)
  data$country <- "Spain"
  raw <- aggregate_behaviour_cells(data, "class")
  testthat::expect_equal(raw$count[raw$gender == "male" & raw$behaviour == "antisocial"], 1)
  public <- aggregate_public_data(data, data)
  cells <- public$cells[public$cells$scope == "class", ]
  get_count <- function(gender, behaviour) {
    cells$count[cells$gender == gender & cells$behaviour == behaviour]
  }
  female_consistent <- unique(stats::na.omit(cells$n_consistent[cells$gender == "female"]))
  operands <- c(get_count("all", "antisocial"), get_count("female", "altruist"),
                get_count("female", "egalitarian"))
  # Previously: 8 - (23 - 6 - 10) exposed the protected male count of one.
  testthat::expect_true(!length(female_consistent) || anyNA(operands))
  testthat::expect_true(is.na(get_count("male", "antisocial")))
})
