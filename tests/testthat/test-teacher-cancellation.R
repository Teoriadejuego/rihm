testthat::test_that("cancelling during one export cleans it and skips the next download", {
  withr::local_envvar(c(TEACHER_HOST_MODE = "cloud", QUALTRICS_API_KEY = "fixture-key",
    QUALTRICS_BASE_URL = "fra1.qualtrics.com"))
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  id <- coordinator$begin("fixture", "update", TRUE)
  on.exit(coordinator$finish(id, "Test cleanup"), add = TRUE)
  cancellation <- coordinator$cancellation(id, "fixture")
  paths <- character()
  surveys <- character()
  request <- function(surveyID, tmp_dir, ...) {
    surveys <<- c(surveys, surveyID)
    paths <<- c(paths, tmp_dir)
    writeLines("synthetic private row", file.path(tmp_dir, "export.csv"))
    coordinator$cancel("fixture")
    data.frame(value = 1L)
  }
  download <- download_surveys_once
  scope <- new.env(parent = environment(download))
  scope$fetch_survey_once <- function(survey_id) fetch_survey_once(survey_id, request)
  environment(download) <- scope
  config <- list(project_root = ".", qualtrics = list(
    reference_survey_id = "SV_REFERENCE", class_survey_id = "SV_CLASS"))
  testthat::expect_error(download(config, check_active = function() teacher_permission_valid(cancellation)),
    "Qualtrics download failed")
  testthat::expect_identical(surveys, "SV_REFERENCE")
  testthat::expect_false(any(dir.exists(paths)))
  testthat::expect_false(file.exists(cancellation$path))
  # Cancellation does not pretend to abort the active request or unlock early.
  testthat::expect_true(coordinator$state()$busy)
  coordinator$finish(id, "Cancelled")
  testthat::expect_false(coordinator$state()$busy)
})

testthat::test_that("revoked or expired workers never start the next expensive phase", {
  worker <- teacher_operation_worker
  scope <- new.env(parent = environment(worker))
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  id <- coordinator$begin("fixture", "update", TRUE)
  on.exit(coordinator$finish(id, "Test cleanup"), add = TRUE)
  cancellation <- coordinator$cancellation(id, "fixture")
  downloads <- 0L
  aggregates <- 0L
  scope$download_surveys_once <- function(config, check_active) {
    downloads <<- downloads + 1L
    coordinator$cancel("fixture")
    list()
  }
  scope$prepare_latest_group_candidate <- function(...) { aggregates <<- aggregates + 1L; stop("Must not aggregate") }
  environment(worker) <- scope
  testthat::expect_error(worker("update", list(), cancellation = cancellation), "cancelled or its permission expired")
  testthat::expect_equal(downloads, 1L)
  testthat::expect_equal(aggregates, 0L)
  testthat::expect_error(worker("update", list(), cancellation = cancellation), "cancelled or its permission expired")
  testthat::expect_equal(downloads, 1L)
  expired <- teacher_create_permission("job-999", as.numeric(Sys.time()) - 1)
  on.exit(teacher_revoke_permission(expired), add = TRUE)
  testthat::expect_error(worker("update", list(), cancellation = expired), "cancelled or its permission expired")
  testthat::expect_equal(downloads, 1L)
})

testthat::test_that("latest-group preparation checks cancellation before building public aggregates", {
  pipeline <- prepare_latest_group_candidate
  scope <- new.env(parent = environment(pipeline))
  active <- TRUE
  reference_prepared <- FALSE
  aggregates <- 0L
  scope$read_reference_locations <- function(config) data.frame(uni = 1, country = "Fixture")
  scope$prepare_latest_class_group <- function(...) list(data = data.frame(), selection = list())
  scope$prepare_survey <- function(...) {
    reference_prepared <<- TRUE
    active <<- FALSE
    list(data = data.frame())
  }
  scope$build_latest_group_results <- function(...) { aggregates <<- aggregates + 1L; stop("Must not aggregate") }
  environment(pipeline) <- scope
  testthat::expect_error(pipeline(list(export_time_zone = "UTC"), list(), check_active = function() active),
    "cancelled or its permission expired")
  testthat::expect_true(reference_prepared)
  testthat::expect_equal(aggregates, 0L)
})

testthat::test_that("computation permissions do not grant publication or survive cleanup", {
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  id <- coordinator$begin("fixture", "update", TRUE)
  cancellation <- coordinator$cancellation(id, "fixture")
  testthat::expect_null(coordinator$state()$job$permission)
  testthat::expect_null(coordinator$cancellation(id, "different-session"))
  publication <- coordinator$grant(id, "fixture", TRUE, as.numeric(Sys.time()) + 60)
  testthat::expect_false(identical(cancellation$path, publication$path))
  testthat::expect_true(teacher_permission_valid(cancellation))
  testthat::expect_true(teacher_permission_valid(publication))
  coordinator$cancel("fixture")
  testthat::expect_false(teacher_permission_valid(cancellation))
  testthat::expect_false(teacher_permission_valid(publication))
  coordinator$finish(id, "Cancelled")
  testthat::expect_false(file.exists(cancellation$path))
  testthat::expect_false(file.exists(publication$path))
})
