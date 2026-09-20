public_behaviours <- c(
  altruist = "Altruist",
  egalitarian = "Egalitarian",
  selfish = "Selfish",
  antisocial = "Antisocial",
  inconsistent = "Inconsistent"
)

slice_definitions <- function(data, scope) {
  countries <- if (identical(scope, "class")) {
    "Class"
  } else {
    c("All Countries", sort(unique(data$country[!is.na(data$country)])))
  }
  genders <- c("all", "female", "male")
  expand.grid(country = countries, gender = genders, stringsAsFactors = FALSE)
}

slice_rows <- function(data, scope, country, gender) {
  keep <- rep(TRUE, nrow(data))
  if (identical(scope, "international") && !identical(country, "All Countries")) {
    keep <- keep & !is.na(data$country) & data$country == country
  }
  if (identical(gender, "female")) keep <- keep & data$gender_code == 1
  if (identical(gender, "male")) keep <- keep & data$gender_code == 2
  data[which(keep %in% TRUE), , drop = FALSE]
}

aggregate_behaviour_cells <- function(data, scope) {
  slices <- slice_definitions(data, scope)
  output <- vector("list", nrow(slices) * length(public_behaviours))
  position <- 1L
  for (i in seq_len(nrow(slices))) {
    subset <- slice_rows(data, scope, slices$country[[i]], slices$gender[[i]])
    n_complete <- sum(subset$binary_decisions, na.rm = TRUE)
    n_consistent <- sum(subset$consistent, na.rm = TRUE)
    for (behaviour in names(public_behaviours)) {
      source_name <- unname(public_behaviours[[behaviour]])
      if (identical(behaviour, "inconsistent")) {
        denominator <- n_complete
        denominator_type <- "complete"
        count <- sum(subset[[source_name]] == 1, na.rm = TRUE)
      } else {
        denominator <- n_consistent
        denominator_type <- "consistent"
        count <- sum(subset[[source_name]] == 1, na.rm = TRUE)
      }
      output[[position]] <- data.frame(
        scope = scope, country = slices$country[[i]], gender = slices$gender[[i]],
        behaviour = behaviour, count = count, denominator_n = denominator,
        percentage = if (denominator > 0) round(100 * count / denominator, 1) else NA_real_,
        denominator_type = denominator_type, n_complete = n_complete,
        n_consistent = n_consistent, suppressed = FALSE,
        stringsAsFactors = FALSE
      )
      position <- position + 1L
    }
  }
  do.call(rbind, output)
}

aggregate_matrix_cells <- function(data, scope) {
  slices <- slice_definitions(data, scope)
  output <- list()
  position <- 1L
  for (i in seq_len(nrow(slices))) {
    subset <- slice_rows(data, scope, slices$country[[i]], slices$gender[[i]])
    denominator <- sum(subset$consistent, na.rm = TRUE)
    for (compassion in 1:4) {
      for (envy in 1:4) {
        count <- sum(
          subset$consistent & subset$compassionincreas == compassion & subset$envyincreas == envy,
          na.rm = TRUE
        )
        output[[position]] <- data.frame(
          scope = scope, country = slices$country[[i]], gender = slices$gender[[i]],
          compassion_level = compassion, envy_level = envy, count = count,
          denominator_n = denominator,
          percentage = if (denominator > 0) round(100 * count / denominator, 1) else NA_real_,
          suppressed = FALSE, stringsAsFactors = FALSE
        )
        position <- position + 1L
      }
    }
  }
  do.call(rbind, output)
}

apply_primary_suppression <- function(data, minimum_cell_size) {
  unsafe <- is.na(data$denominator_n) |
    data$denominator_n < minimum_cell_size |
    data$count < minimum_cell_size |
    (data$denominator_n - data$count) < minimum_cell_size
  data$suppressed <- unsafe
  data
}

suppress_one_more <- function(data, indexes) {
  visible <- indexes[!data$suppressed[indexes]]
  if (!length(visible)) return(data)
  counts <- data$count[visible]
  chosen <- visible[order(counts, decreasing = FALSE, na.last = TRUE)[[1L]]]
  data$suppressed[chosen] <- TRUE
  data
}

apply_secondary_suppression <- function(data, value_dimensions) {
  measure_names <- c("count", "denominator_n", "percentage", "n_complete", "n_consistent", "suppressed")
  dimension_names <- setdiff(names(data), measure_names)
  repeat {
    before <- sum(data$suppressed)

    if ("gender" %in% value_dimensions) {
      key_names <- setdiff(dimension_names, "gender")
      keys <- unique(data[key_names])
      for (i in seq_len(nrow(keys))) {
        match_key <- rep(TRUE, nrow(data))
        for (name in key_names) match_key <- match_key & data[[name]] == keys[[name]][[i]]
        indexes <- which(match_key & data$gender %in% c("all", "female", "male"))
        if (length(indexes) == 3L && sum(data$suppressed[indexes]) == 1L) {
          data <- suppress_one_more(data, indexes)
        }
      }
    }

    if ("country" %in% value_dimensions && any(data$country == "All Countries")) {
      key_names <- setdiff(dimension_names, "country")
      keys <- unique(data[key_names])
      for (i in seq_len(nrow(keys))) {
        match_key <- rep(TRUE, nrow(data))
        for (name in key_names) match_key <- match_key & data[[name]] == keys[[name]][[i]]
        indexes <- which(match_key)
        has_total <- any(data$country[indexes] == "All Countries")
        if (has_total && length(indexes) > 2L && sum(data$suppressed[indexes]) == 1L) {
          data <- suppress_one_more(data, indexes)
        }
      }
    }
    if (sum(data$suppressed) == before) break
  }
  data
}

apply_matrix_complement_suppression <- function(data) {
  keys <- unique(data[c("scope", "country", "gender")])
  for (i in seq_len(nrow(keys))) {
    indexes <- which(
      data$scope == keys$scope[[i]] &
        data$country == keys$country[[i]] &
        data$gender == keys$gender[[i]]
    )
    if (length(indexes) == 16L && sum(data$suppressed[indexes]) == 1L) {
      data <- suppress_one_more(data, indexes)
    }
  }
  data
}

protect_inconsistent_totals <- function(data) {
  keys <- unique(data[c("scope", "country", "gender")])
  for (i in seq_len(nrow(keys))) {
    indexes <- which(
      data$scope == keys$scope[[i]] &
        data$country == keys$country[[i]] &
        data$gender == keys$gender[[i]]
    )
    inconsistent <- indexes[data$behaviour[indexes] == "inconsistent"]
    if (length(inconsistent) == 1L && data$suppressed[inconsistent]) {
      data$n_complete[indexes] <- NA_real_
    }
  }
  data
}

redact_suppressed <- function(data) {
  numeric_fields <- intersect(c("count", "denominator_n", "percentage", "n_complete", "n_consistent"), names(data))
  for (name in numeric_fields) data[[name]][data$suppressed] <- NA
  data
}

aggregate_public_data <- function(class_data, reference_data, minimum_cell_size = 5L) {
  cells <- rbind(
    aggregate_behaviour_cells(class_data, "class"),
    aggregate_behaviour_cells(reference_data, "international")
  )
  cells <- apply_primary_suppression(cells, minimum_cell_size)
  cells <- apply_secondary_suppression(cells, c("gender", "country"))
  cells <- protect_inconsistent_totals(cells)
  cells <- redact_suppressed(cells)

  matrix_cells <- rbind(
    aggregate_matrix_cells(class_data, "class"),
    aggregate_matrix_cells(reference_data, "international")
  )
  matrix_cells <- apply_primary_suppression(matrix_cells, minimum_cell_size)
  matrix_cells <- apply_matrix_complement_suppression(matrix_cells)
  matrix_cells <- apply_secondary_suppression(matrix_cells, c("gender", "country"))
  matrix_cells <- redact_suppressed(matrix_cells)
  list(cells = cells, matrix_cells = matrix_cells)
}
