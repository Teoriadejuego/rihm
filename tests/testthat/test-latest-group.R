testthat::test_that("latest group is the historical source hour with exact open and closed bounds", {
  raw <- make_raw_pairs(binary_grid()[1:7, ])
  raw$EndDate <- c("2001-02-03 12:00:00", "2001-02-03 12:00:00.001",
    "2001-02-03T12:30:00Z", "2001-02-03T13:00:00Z", NA, "not a date",
    "2001-02-03T13:00:00+02:00")
  raw$dic10_6[[4L]] <- 2 # This excluded statistical response still anchors T.
  group <- prepare_latest_class_group(raw, test_locations())
  testthat::expect_identical(group$data$row_index, 2:4)
  testthat::expect_identical(group$selection$window_start_utc, "2001-02-03T12:00:00Z")
  testthat::expect_identical(group$selection$window_end_utc, "2001-02-03T13:00:00Z")
  testthat::expect_identical(group$selection$invalid_end_dates, 2L)
  testthat::expect_identical(group$selection$outside_window_rows, 2L)
  testthat::expect_false(tail(group$data$binary_decisions, 1L))
})

testthat::test_that("deduplication precedes selection and missing EndDate never uses RecordedDate", {
  raw <- make_raw_dic(binary_grid()[1:4, ])
  raw$ResponseId <- c("duplicate", "duplicate", "third", "fourth")
  raw$EndDate <- c("2000-01-01 10:30:00", "2000-01-01 11:30:00", "2000-01-01 11:00:00", NA)
  raw$RecordedDate <- rep("2099-01-01 12:00:00", 4)
  selected <- prepare_latest_class_group(raw, test_locations())
  testthat::expect_identical(selected$data$row_index, 2:3)
  testthat::expect_identical(selected$selection$deduplicated_rows, 3L)
  testthat::expect_identical(selected$selection$invalid_end_dates, 1L)
  testthat::expect_identical(selected$selection$window_end_utc, "2000-01-01T11:30:00Z")
  raw$EndDate <- NULL
  testthat::expect_error(prepare_latest_class_group(raw, test_locations()), "no valid EndDate")
  raw$EndDate <- rep("2026-02-30 00:00:00", 4)
  testthat::expect_error(prepare_latest_class_group(raw, test_locations()), "no valid EndDate")
})

testthat::test_that("UTC parsing honours offsets and rejects invalid calendar dates independently of host TZ", {
  withr::local_envvar(TZ = "Pacific/Auckland")
  input <- c("2024-02-29 12:00:00", "2024-02-29T14:00:00+02:00",
    "2024-02-29T070000-0500", "2025-02-29 12:00:00", "2024-02-29T12:00:00+14:30")
  parsed <- parse_qualtrics_end_date(input)
  testthat::expect_identical(format_utc_timestamp(parsed[1:2]), rep("2024-02-29T12:00:00Z", 2))
  testthat::expect_true(all(is.na(parsed[3:5])))
  testthat::expect_identical(format_utc_timestamp(parse_qualtrics_end_date("2024-02-29T07:00:00-0500")),
    "2024-02-29T12:00:00Z")
  testthat::expect_identical(format_utc_timestamp(parse_qualtrics_end_date("2024-02-29T12:00:00.125Z")),
    "2024-02-29T12:00:00.125Z")
})

testthat::test_that("latest candidate retains the full historical reference and emits source provenance", {
  root <- tempfile("latest-candidate-")
  dir.create(root)
  locations <- file.path(root, "reference_locations.csv")
  utils::write.csv(test_locations(), locations, row.names = FALSE)
  config <- list(locations_file = locations, privacy = list(minimum_cell_size = 5L),
    qualtrics = list(session_code_column = "session_password"))
  decisions <- binary_grid()[rep(1:64, each = 10), ]
  class <- make_raw_pairs(decisions, session = "PRIVATE-SESSION")
  class$EndDate <- rep("2001-01-01 12:00:00", nrow(class))
  reference <- make_raw_dic(decisions)
  reference$EndDate <- rep("1990-01-01 00:00:00", nrow(reference))
  downloaded <- list(class = class, reference = reference, export_time_zone = "UTC",
    class_source_at_utc = "2026-11-17T12:01:00Z", reference_source_at_utc = "2026-11-17T12:00:00Z")
  candidate <- prepare_latest_group_candidate(downloaded, config)
  testthat::expect_equal(nrow(candidate$reference$data), nrow(reference))
  testthat::expect_equal(nrow(candidate$class$data), nrow(class))
  testthat::expect_identical(candidate$results$metadata$schema_version, "2.0.0")
  testthat::expect_identical(candidate$results$metadata$class_source_at_utc, downloaded$class_source_at_utc)
  testthat::expect_identical(candidate$results$metadata$reference_source_at_utc, downloaded$reference_source_at_utc)
  testthat::expect_silent(validate_github_public_results(candidate$results, "PRIVATE-SESSION"))
  downloaded$export_time_zone <- "Europe/Madrid"
  testthat::expect_error(prepare_latest_group_candidate(downloaded, config), "UTC Qualtrics export")
})
