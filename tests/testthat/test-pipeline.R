testthat::test_that("a downloaded pair of surveys becomes a safe immutable candidate", {
  decisions <- binary_grid()[rep(seq_len(64), each = 10), ]
  downloaded <- list(
    class = make_raw_pairs(decisions, session = "PRIVATE-CODE", country_uni = 18, gender = 1),
    reference = rbind(
      make_raw_dic(decisions, session = "unused", country_uni = 18, gender = 1),
      transform(make_raw_dic(decisions, session = "unused", country_uni = 29, gender = 2),
                ResponseId = paste0("S_", seq_len(nrow(decisions))))
    ),
    downloaded_at_utc = "2026-09-20T10:00:00Z"
  )
  temporary <- tempfile("pipeline-project-")
  dir.create(file.path(temporary, "config"), recursive = TRUE)
  utils::write.csv(test_locations(), file.path(temporary, "config", "reference_locations.csv"), row.names = FALSE)
  config <- list(
    project_root = temporary,
    locations_file = file.path(temporary, "config", "reference_locations.csv"),
    qualtrics = list(session_code_column = "session_password"),
    privacy = list(minimum_cell_size = 5L)
  )

  candidate <- prepare_publication_candidate(downloaded, "private-code", config)
  testthat::expect_equal(candidate$class$schema, "dic_pairs")
  testthat::expect_equal(candidate$reference$schema, "DIC")
  testthat::expect_true(nrow(candidate$results$cells) > 0)
  testthat::expect_silent(assert_public_safe(candidate$results, "PRIVATE-CODE"))
})

testthat::test_that("empty survey downloads fail before publication", {
  testthat::expect_error(
    normalise_survey(data.frame(), "class", test_locations()),
    "returned no rows"
  )
})

