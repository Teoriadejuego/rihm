testthat::test_that("clock ticks do not rerender snapshots or resend unchanged controls", {
  clock <- 1000
  service <- make_teacher_reactive_coordinator(cooldown_seconds = 10, now = function() clock)
  coordinator <- service$coordinator
  snapshot <- list(metadata = list(publication_id = "fixture"), cells = data.frame(count = 10L))
  read <- coordinator$begin("fixture", "refresh", TRUE)
  coordinator$finish(read, "Loaded", published = snapshot)
  renders <- 0L
  messages <- list()
  shiny::testServer(function(input, output, session) {
    cooldown <- service$cooldown(session)
    send <- make_teacher_control_sender(function(type, value) messages[[length(messages) + 1L]] <<- value)
    shiny::observe(send(teacher_control_state(service$state(), cooldown(), "fixture")))
    output$clock <- shiny::renderText(cooldown())
    output$table <- shiny::renderTable({
      renders <<- renders + 1L
      service$snapshot()$cells
    })
  }, {
    session$flushReact()
    invisible(output$table)
    for (i in 1:5) {
      clock <<- clock + 1
      session$elapse(1000)
      session$flushReact()
      invisible(output$table)
    }
    testthat::expect_equal(output$clock, "5")
    testthat::expect_equal(renders, 1L)
    testthat::expect_length(messages, 1L)
    testthat::expect_false(messages[[1L]]$update_publish)

    demo <- coordinator$begin("fixture", "demo", TRUE)
    session$flushReact() # Lock transitions are immediate, without advancing time.
    testthat::expect_length(messages, 2L)
    testthat::expect_false(messages[[2L]]$load_demo)
    coordinator$finish(demo, "Done")
    session$flushReact()
    testthat::expect_length(messages, 3L)
    for (i in 1:5) {
      clock <<- clock + 1
      session$elapse(1000)
      session$flushReact()
    }
    testthat::expect_equal(output$clock, "0")
    testthat::expect_length(messages, 4L)
    testthat::expect_true(messages[[4L]]$update_publish)
    testthat::expect_equal(renders, 1L)

    read <- coordinator$begin("fixture", "refresh", TRUE)
    coordinator$finish(read, "Same verified snapshot", published = snapshot)
    session$flushReact()
    invisible(output$table)
    testthat::expect_equal(renders, 1L)
    changed <- snapshot
    changed$metadata$publication_id <- "new-fixture"
    changed$cells$count <- 12L
    read <- coordinator$begin("fixture", "refresh", TRUE)
    coordinator$finish(read, "New snapshot", published = changed)
    session$flushReact()
    invisible(output$table)
    testthat::expect_equal(renders, 2L)
  })
})

testthat::test_that("a new authenticated UI gets controls even when their values match the prior login", {
  messages <- 0L
  send <- make_teacher_control_sender(function(type, value) messages <<- messages + 1L)
  controls <- list(update_publish = TRUE, load_demo = TRUE, refresh_latest = TRUE, cancel_operation = FALSE)
  testthat::expect_true(send(controls))
  testthat::expect_false(send(controls))
  send(reset = TRUE)
  testthat::expect_true(send(controls))
  testthat::expect_equal(messages, 2L)
})

testthat::test_that("two waiting sessions share one restoration and logout drops the request", {
  service <- make_teacher_reactive_coordinator(cooldown_seconds = 0)
  coordinator <- service$coordinator
  hold <- coordinator$begin("other-operation", "demo", TRUE)
  calls <- c(a = 0L, b = 0L)
  active_read <- NULL
  shiny::testServer(function(input, output, session) {
    pending_a <- shiny::reactiveVal(TRUE)
    pending_b <- shiny::reactiveVal(TRUE)
    auth_a <- shiny::reactiveVal(TRUE)
    auth_b <- shiny::reactiveVal(TRUE)
    revision_a <- shiny::reactiveVal(0L)
    revision_b <- shiny::reactiveVal(0L)
    install <- function(owner, pending, auth, revision) shiny::observe({
      action <- teacher_restore_action(pending(), auth(), service$state(), revision())
      if (action == "reuse") pending(FALSE)
      if (action == "refresh") {
        pending(FALSE)
        calls[[owner]] <<- calls[[owner]] + 1L
        active_read <<- coordinator$begin(owner, "refresh", auth())
      }
    })
    install("a", pending_a, auth_a, revision_a)
    install("b", pending_b, auth_b, revision_b)
  }, {
    session$flushReact()
    testthat::expect_equal(sum(calls), 0L)
    coordinator$finish(hold, "Other operation ended")
    session$flushReact()
    testthat::expect_equal(sum(calls), 1L)
    coordinator$finish(active_read, "Restored", published = list(metadata = list(publication_id = "verified")))
    session$flushReact()
    testthat::expect_false(pending_a())
    testthat::expect_false(pending_b())
    testthat::expect_equal(sum(calls), 1L)

    hold <- coordinator$begin("other-operation", "demo", TRUE)
    revision_b(coordinator$state()$confirmed_revision)
    pending_b(TRUE)
    session$flushReact()
    auth_b(FALSE)
    coordinator$finish(hold, "Other operation ended")
    session$flushReact()
    testthat::expect_equal(sum(calls), 1L)
    testthat::expect_false(coordinator$state()$busy)
  })
})

testthat::test_that("notification failures cannot retain a lock or operation markers", {
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0,
    on_change = function(state) stop("synthetic detached observer"))
  id <- coordinator$begin("fixture", "update", TRUE)
  cancellation <- coordinator$cancellation(id, "fixture")
  publication <- coordinator$grant(id, "fixture", TRUE, as.numeric(Sys.time()) + 60)
  testthat::expect_true(file.exists(cancellation$path))
  testthat::expect_silent(coordinator$finish(id, "Finished"))
  testthat::expect_false(coordinator$state()$busy)
  testthat::expect_false(file.exists(cancellation$path))
  testthat::expect_false(file.exists(publication$path))
})

testthat::test_that("refresh reads only Pages and preserves a known pending commit", {
  worker <- teacher_operation_worker
  scope <- new.env(parent = environment(worker))
  scope$get_current_published_results <- function(config) list(metadata = list(publication_id = "pages-old"))
  scope$get_current_github_results <- function(config) stop("GitHub must not be consulted during restoration")
  environment(worker) <- scope
  value <- worker("refresh", list())
  testthat::expect_identical(value$results$metadata$publication_id, "pages-old")
  testthat::expect_false("committed" %in% names(value))
  coordinator <- make_teacher_coordinator(cooldown_seconds = 0)
  id <- coordinator$begin("fixture", "update", TRUE)
  saved <- list(metadata = list(publication_id = "pending-new"))
  coordinator$finish(id, "Saved but unconfirmed", saved = saved)
  id <- coordinator$begin("fixture", "refresh", TRUE)
  teacher_finish_public_operation(coordinator, id, value)
  testthat::expect_identical(coordinator$state()$committed, saved)
  testthat::expect_identical(coordinator$state()$latest, value$results)
})
