decision_columns <- paste0("DP", 1:6)

classify_preferences <- function(data) {
  missing <- setdiff(decision_columns, names(data))
  if (length(missing)) {
    stop("Missing normalised decisions: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  values <- data[decision_columns]
  complete <- stats::complete.cases(values)
  binary <- complete & apply(values, 1L, function(row) all(row %in% c(0, 1)))

  envy <- rep(NA_integer_, nrow(data))
  envy[binary & data$DP3 == 1 & data$DP4 == 1 & data$DP6 == 1] <- 1L
  envy[binary & data$DP3 == 1 & data$DP4 == 1 & data$DP6 == 0] <- 2L
  envy[binary & data$DP3 == 0 & data$DP4 == 1 & data$DP6 == 0] <- 3L
  envy[binary & data$DP3 == 0 & data$DP4 == 0 & data$DP6 == 0] <- 4L

  compassion <- rep(NA_integer_, nrow(data))
  compassion[binary & data$DP1 == 1 & data$DP2 == 1 & data$DP5 == 1] <- 1L
  compassion[binary & data$DP1 == 0 & data$DP2 == 1 & data$DP5 == 1] <- 2L
  compassion[binary & data$DP1 == 0 & data$DP2 == 1 & data$DP5 == 0] <- 3L
  compassion[binary & data$DP1 == 0 & data$DP2 == 0 & data$DP5 == 0] <- 4L

  inconsistent <- binary & (is.na(envy) | is.na(compassion))
  consistent <- binary & !inconsistent
  indicator <- function(condition) {
    result <- rep(NA_integer_, nrow(data))
    result[consistent] <- as.integer(condition[consistent])
    result
  }

  data$complete_decisions <- complete
  data$binary_decisions <- binary
  data$envyincreas <- envy
  data$compassionincreas <- compassion
  data$Inconsistent <- ifelse(binary, as.integer(inconsistent), NA_integer_)
  data$consistent <- consistent
  data$Selfish <- indicator(compassion >= 1 & compassion <= 2 & envy >= 2 & envy <= 3)
  data$Spiteful <- indicator(compassion == 1 & envy >= 3 & envy <= 4)
  data$Egalitarian <- indicator(compassion >= 2 & compassion <= 4 & envy >= 3 & envy <= 4)
  data$dp_efficiency <- indicator(compassion >= 2 & envy >= 1 & envy <= 2)
  data$Altruist <- indicator(compassion >= 2 & compassion <= 4 & envy >= 1 & envy <= 2)
  data$Ineqseek <- indicator(compassion == 1 & envy >= 1 & envy <= 2)
  data$Antisocial <- indicator(data$Spiteful == 1 | data$Ineqseek == 1)
  data
}

