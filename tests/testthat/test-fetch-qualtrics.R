qualtrics_test_download <- function(request) {
  download <- download_surveys_once
  mock_scope <- new.env(parent = environment(download))
  mock_scope$fetch_survey_once <- request
  environment(download) <- mock_scope
  download
}

qualtrics_test_config <- function() list(project_root = ".", qualtrics = list(
  reference_survey_id = "SV_REFERENCE", class_survey_id = "SV_CLASS"
))

testthat::test_that("Qualtrics credentials accept only a vendor data-center hostname", {
  testthat::expect_silent(validate_qualtrics_credentials(list(api_key = "test-key", base_url = "fra1.qualtrics.com")))
  for (host in c("https://fra1.qualtrics.com", "fra1.qualtrics.com/API/v3", "localhost",
                 "fra1.qualtrics.com.evil.example", "fra1.qualtrics.com@evil.example",
                 "fra1.qualtrics.com:443", "org.fra1.qualtrics.com")) {
    testthat::expect_error(validate_qualtrics_credentials(list(api_key = "test-key", base_url = host)), "data-center hostname")
  }
})

testthat::test_that("per-request credentials are restored after both success and a sanitized failure", {
  withr::local_envvar(c(QUALTRICS_API_KEY = "previous-key", QUALTRICS_BASE_URL = "previous.qualtrics.com",
    TEACHER_HOST_MODE = "cloud"))
  credentials <- list(api_key = "private-test-key", base_url = "fra1.qualtrics.com")
  calls <- character()
  download <- qualtrics_test_download(function(survey_id) {
    testthat::expect_identical(Sys.getenv("QUALTRICS_API_KEY"), credentials$api_key)
    testthat::expect_identical(Sys.getenv("QUALTRICS_BASE_URL"), credentials$base_url)
    calls <<- c(calls, survey_id)
    data.frame(value = 1L)
  })
  result <- download(qualtrics_test_config(), credentials)
  testthat::expect_identical(calls, c("SV_REFERENCE", "SV_CLASS"))
  testthat::expect_equal(nrow(result$class), 1L)
  testthat::expect_identical(Sys.getenv("QUALTRICS_API_KEY"), "previous-key")
  testthat::expect_identical(Sys.getenv("QUALTRICS_BASE_URL"), "previous.qualtrics.com")
  failing <- qualtrics_test_download(function(survey_id) {
    message(credentials$api_key)
    warning(credentials$api_key)
    stop(credentials$api_key)
  })
  captured <- NULL
  testthat::expect_silent(captured <- tryCatch(failing(qualtrics_test_config(), credentials), error = identity))
  testthat::expect_s3_class(captured, "error")
  testthat::expect_match(conditionMessage(captured), "^Qualtrics download failed")
  testthat::expect_false(grepl(credentials$api_key, conditionMessage(captured), fixed = TRUE))
  testthat::expect_identical(Sys.getenv("QUALTRICS_API_KEY"), "previous-key")
  testthat::expect_identical(Sys.getenv("QUALTRICS_BASE_URL"), "previous.qualtrics.com")
})

testthat::test_that("absent credentials remain absent after a per-request download", {
  withr::local_envvar(c(QUALTRICS_API_KEY = NA_character_, QUALTRICS_BASE_URL = NA_character_,
    TEACHER_HOST_MODE = "cloud"))
  download <- qualtrics_test_download(function(survey_id) data.frame(value = 1L))
  download(qualtrics_test_config(), list(api_key = "private-test-key", base_url = "fra1.qualtrics.com"))
  testthat::expect_true(is.na(Sys.getenv("QUALTRICS_API_KEY", unset = NA_character_)))
  testthat::expect_true(is.na(Sys.getenv("QUALTRICS_BASE_URL", unset = NA_character_)))
})

testthat::test_that("each fetch deletes its private temporary directory even on failure", {
  withr::local_envvar(c(QUALTRICS_API_KEY = "test-key", QUALTRICS_BASE_URL = "fra1.qualtrics.com"))
  paths <- character()
  request <- function(surveyID, convert, label, verbose, tmp_dir) {
    testthat::expect_false(convert)
    testthat::expect_false(label)
    testthat::expect_false(verbose)
    testthat::expect_true(dir.exists(tmp_dir))
    paths <<- c(paths, tmp_dir)
    writeLines("synthetic private test", file.path(tmp_dir, "export.csv"))
    if (length(paths) == 2L) stop("synthetic transport failure")
    data.frame(value = 1L)
  }
  testthat::expect_equal(nrow(fetch_survey_once("SV_TEST", request)), 1L)
  testthat::expect_error(fetch_survey_once("SV_TEST", request), "synthetic transport failure")
  testthat::expect_equal(length(unique(paths)), 2L)
  testthat::expect_false(any(dir.exists(paths)))
  testthat::expect_error(remove_qualtrics_temp_directory(tempdir(), tempdir()), "Refusing")
  testthat::expect_true(dir.exists(tempdir()))
})
