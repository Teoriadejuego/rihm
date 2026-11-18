testthat::test_that("the global lock and cooldown span sessions and start conservatively", {
  clock <- 1000
  coordinator <- make_teacher_coordinator(now = function() clock)
  testthat::expect_equal(coordinator$state()$cooldown_remaining, 180L)
  testthat::expect_error(coordinator$begin("a", "update", TRUE), "cooldown")
  read <- coordinator$begin("a", "refresh", TRUE)
  testthat::expect_error(coordinator$begin("b", "demo", TRUE), "Another operation")
  coordinator$finish(read, "Read complete")
  clock <- 1180
  update <- coordinator$begin("b", "update", TRUE)
  testthat::expect_equal(coordinator$state()$cooldown_remaining, 180L)
  testthat::expect_error(coordinator$begin("a", "update", TRUE), "Another operation")
  coordinator$finish(update, "Download failed")
  testthat::expect_error(coordinator$begin("a", "update", TRUE), "cooldown")
  clock <- 1359
  testthat::expect_equal(coordinator$state()$cooldown_remaining, 1L)
  clock <- 1360
  testthat::expect_type(coordinator$begin("a", "update", TRUE), "character")
  restarted <- make_teacher_coordinator(now = function() clock)
  testthat::expect_equal(restarted$state()$cooldown_remaining, 180L)
})

testthat::test_that("publication needs the original active owner and live authentication", {
  clock <- 1000
  guard <- make_teacher_session_guard(900, now = function() clock)
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0, now = function() clock)
  testthat::expect_error(coordinator$begin("a", "update", guard$authenticated()), "Sign in")
  guard$login()
  id <- coordinator$begin("a", "update", guard$authenticated())
  testthat::expect_true(coordinator$may_publish(id, "a", guard$authenticated()))
  testthat::expect_false(coordinator$may_publish(id, "b", TRUE))
  testthat::expect_false(coordinator$may_publish("job-forged", "a", TRUE))
  guard$logout()
  testthat::expect_false(coordinator$may_publish(id, "a", guard$authenticated()))
  testthat::expect_error(coordinator$grant(id, "a", guard$authenticated(), 1800), "authorised")
  guard$login()
  clock <- 1900
  testthat::expect_false(coordinator$may_publish(id, "a", guard$authenticated()))
  testthat::expect_error(coordinator$grant(id, "a", TRUE, 1900), "authorised")
})

testthat::test_that("revocation stops pending writes but does not lose a completed commit", {
  clock <- 1000
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0, now = function() clock)
  id <- coordinator$begin("a", "update", TRUE)
  permission <- coordinator$grant(id, "a", TRUE, 1800)
  testthat::expect_true(teacher_permission_valid(permission, now = 1000))
  testthat::expect_false(coordinator$cancel("b"))
  testthat::expect_true(teacher_permission_valid(permission, now = 1000))
  testthat::expect_true(coordinator$cancel("a"))
  testthat::expect_false(teacher_permission_valid(permission, now = 1000))
  testthat::expect_false(coordinator$may_publish(id, "a", TRUE))
  testthat::expect_error(coordinator$grant(id, "a", TRUE, 1800), "authorised")
  testthat::expect_true(coordinator$state()$busy)
  testthat::expect_error(coordinator$begin("b", "refresh", TRUE), "Another operation")
  testthat::expect_false(coordinator$finish("job-forged", "Stale completion"))
  committed <- list(metadata = list(publication_id = "committed-before-cancel"), cells = list())
  testthat::expect_true(coordinator$finish(id, "Committed and reconciled", published = committed))
  testthat::expect_false(coordinator$state()$busy)
  testthat::expect_identical(coordinator$state()$latest, committed)
})

testthat::test_that("worker permissions expire without a browser heartbeat or timer", {
  permission <- teacher_create_permission("job-1", 2000)
  on.exit(teacher_revoke_permission(permission), add = TRUE)
  testthat::expect_true(teacher_permission_valid(permission, now = 1999))
  testthat::expect_false(teacher_permission_valid(permission, now = 2000))
  forged <- permission
  forged$job_id <- "job-2"
  testthat::expect_false(teacher_permission_valid(forged, now = 1999))
  testthat::expect_setequal(names(readRDS(permission$path)), c("job_id", "expires_at"))
  saveRDS(list(job_id = "job-1", expires_at = NA_real_), permission$path)
  testthat::expect_false(teacher_permission_valid(permission, now = 1999))
  unrelated <- tempfile("unrelated-marker-")
  writeLines("preserve", unrelated)
  on.exit(unlink(unrelated), add = TRUE)
  teacher_revoke_permission(list(path = unrelated))
  testthat::expect_true(file.exists(unrelated))
})

testthat::test_that("demonstrations and read operations cannot obtain publication permits", {
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  for (kind in c("demo", "refresh")) {
    id <- coordinator$begin("a", kind, TRUE)
    testthat::expect_false(coordinator$may_publish(id, "a", TRUE))
    testthat::expect_error(coordinator$grant(id, "a", TRUE, as.numeric(Sys.time()) + 60), "authorised")
    coordinator$finish(id, "Finished")
  }
  testthat::expect_error(teacher_operation_worker("publish", list(),
    results = list(metadata = list(data_mode = "demonstration"))), "cannot be published")
})

testthat::test_that("only protected aggregates and diagnostics leave the compute worker", {
  private <- list(data = data.frame(response_id = "PRIVATE-ROW-ID", value = 1),
    duplicate_ids = "PRIVATE-DUPLICATE-ID", schema = "private-schema",
    diagnostics = data.frame(metric = "Complete binary responses", value = 20))
  source <- list(results = list(metadata = list(data_mode = "real"), cells = list(), matrix_cells = list()),
    class = private, reference = private, selection = list(selected_rows = 20L))
  preview <- teacher_candidate_preview(source)
  testthat::expect_setequal(names(preview), c("results", "diagnostics", "selection", "demonstration"))
  testthat::expect_equal(nrow(preview$diagnostics), 2L)
  serialised <- jsonlite::toJSON(preview)
  testthat::expect_false(grepl("PRIVATE-ROW-ID|PRIVATE-DUPLICATE-ID|private-schema", serialised))
  testthat::expect_false(preview$demonstration)
})

testthat::test_that("pending commits cannot replace the last confirmed presentation snapshot", {
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  snapshot <- function(id) list(metadata = list(publication_id = id))
  old <- snapshot("confirmed-old")
  pending <- snapshot("saved-new")
  id <- coordinator$begin("a", "refresh", TRUE)
  teacher_finish_public_operation(coordinator, id,
    list(type = "refreshed", results = old, committed = old))
  id <- coordinator$begin("a", "update", TRUE)
  coordinator$cancel("a")
  message <- teacher_finish_public_operation(coordinator, id, list(type = "published",
    publication = list(results = pending, changed = TRUE, deployment = list(verified = FALSE))))
  testthat::expect_match(message, "pending or unconfirmed")
  testthat::expect_false(coordinator$state()$busy)
  testthat::expect_identical(coordinator$state()$latest, old)
  testthat::expect_identical(coordinator$state()$committed, pending)
  id <- coordinator$begin("b", "refresh", TRUE)
  teacher_finish_public_operation(coordinator, id,
    list(type = "refreshed", results = old, committed = pending))
  testthat::expect_identical(coordinator$state()$latest, old)
  id <- coordinator$begin("b", "update", TRUE)
  teacher_finish_public_operation(coordinator, id, list(type = "published",
    publication = list(results = pending, changed = FALSE, deployment = list(verified = TRUE))))
  testthat::expect_identical(coordinator$state()$latest, pending)
  testthat::expect_false(coordinator$state()$busy)
})

testthat::test_that("the real async panel keeps demonstrations private and clears them on logout", {
  root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
  withr::local_dir(root)
  withr::local_envvar(c(TEACHER_HOST_MODE = "cloud", TEACHER_USERNAME = "fixture",
    TEACHER_PASSWORD = "Test-only-panel-password-12345", GITHUB_PUBLICATION_TOKEN = "",
    QUALTRICS_API_KEY = "", QUALTRICS_BASE_URL = ""))
  previous_plan <- future::plan()
  on.exit(future::plan(previous_plan), add = TRUE)
  # The login restoration is intentionally held; this test never contacts
  # GitHub or Qualtrics, but uses the actual separate-process demo calculation.
  environment <- new.env(parent = globalenv())
  sys.source(file.path(root, "admin", "app.R"), envir = environment)
  coordinator <- environment$teacher_coordinator
  hold <- coordinator$begin("test-hold", "demo", TRUE)
  shiny::testServer(environment$server, {
    wait_complete <- function(limit = 45) {
      deadline <- Sys.time() + limit
      while (coordinator$state()$busy && Sys.time() < deadline) {
        later::run_now(0.05)
        session$flushReact()
      }
      testthat::expect_false(coordinator$state()$busy)
    }
    session$flushReact()
    session$setInputs(update_publish = 1)
    testthat::expect_identical(coordinator$state()$job$owner, "test-hold")
    session$setInputs(`teacher_login-user_id` = "fixture",
      `teacher_login-user_pwd` = "Test-only-panel-password-12345", `teacher_login-go_auth` = 1)
    testthat::expect_true(authenticated())
    restore_pending(FALSE) # Restoration has its own mocked tests below.
    coordinator$finish(hold, "Read restoration held for isolated test")
    session$setInputs(load_demo = 1)
    wait_complete()
    testthat::expect_true(candidate()$demonstration)
    testthat::expect_null(coordinator$state()$latest)
    first <- candidate()$results
    first$metadata$publication_id <- "first-confirmed-fixture"
    hold_snapshot <- coordinator$begin("snapshot-fixture", "refresh", TRUE)
    coordinator$finish(hold_snapshot, "Fixture confirmed", published = first)
    session$setInputs(presentation_started = 1, slide_next = 1)
    testthat::expect_true(presenting())
    testthat::expect_equal(slide(), 2L)
    second <- first
    second$metadata$publication_id <- "second-confirmed-fixture"
    hold_snapshot <- coordinator$begin("snapshot-fixture", "refresh", TRUE)
    coordinator$finish(hold_snapshot, "New fixture confirmed", published = second)
    testthat::expect_identical(projected()$metadata$publication_id, "first-confirmed-fixture")
    session$setInputs(teacher_logout = 1)
    testthat::expect_false(authenticated())
    testthat::expect_null(candidate())
    testthat::expect_false(presenting())
    session$setInputs(load_demo = 2, update_publish = 2)
    testthat::expect_false(coordinator$state()$busy)
    hold_again <- coordinator$begin("test-hold", "demo", TRUE)
    session$setInputs(`teacher_login-user_pwd` = "Test-only-panel-password-12345", `teacher_login-go_auth` = 2)
    restore_pending(FALSE)
    coordinator$finish(hold_again, "Read restoration held for isolated test")
    session$setInputs(load_demo = 3)
    testthat::expect_true(coordinator$state()$busy)
    session$close()
  })
  # No session observers are flushed: the global promise callback alone must
  # revoke/finish the disconnected operation and preserve confirmed aggregates.
  deadline <- Sys.time() + 45
  while (coordinator$state()$busy && Sys.time() < deadline) later::run_now(0.05)
  testthat::expect_false(coordinator$state()$busy)
  testthat::expect_identical(coordinator$state()$latest$metadata$publication_id, "second-confirmed-fixture")
})
