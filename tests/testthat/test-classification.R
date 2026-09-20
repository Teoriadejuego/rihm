testthat::test_that("the original 64-pattern classification is preserved", {
  classified <- classify_preferences(binary_grid())
  testthat::expect_equal(sum(classified$consistent), 16)
  testthat::expect_equal(sum(classified$Inconsistent == 1), 48)
  testthat::expect_identical(classified$dp_efficiency, classified$Altruist)

  visible <- classified[c("Selfish", "Egalitarian", "Altruist", "Antisocial")]
  labels <- rowSums(visible, na.rm = TRUE)
  testthat::expect_equal(sum(labels[classified$consistent] == 1), 12)
  testthat::expect_equal(sum(labels[classified$consistent] == 2), 4)
  testthat::expect_equal(sum(labels[classified$consistent] == 0), 0)
})

testthat::test_that("partial and non-binary responses are excluded", {
  data <- binary_grid()[1:3, ]
  data$DP1[[1]] <- NA
  data$DP2[[2]] <- 9
  classified <- classify_preferences(data)
  testthat::expect_false(classified$complete_decisions[[1]])
  testthat::expect_false(classified$binary_decisions[[2]])
  testthat::expect_true(is.na(classified$Inconsistent[[1]]))
  testthat::expect_true(is.na(classified$Altruist[[2]]))
})

