testthat::test_that("teacher credentials fail closed and match the public module contract", {
  testthat::expect_error(make_teacher_auth_checker("short", "profesor"), "at least 20")
  testthat::expect_error(make_teacher_auth_checker(strrep("x", 24), NA_character_), "TEACHER_USERNAME")
  check <- make_teacher_auth_checker("Test-only-password-123456", "profesor")
  testthat::expect_false(check("unknown", "Test-only-password-123456")$result)
  result <- check("profesor", "Test-only-password-123456")
  testthat::expect_true(result$result)
  testthat::expect_identical(result$user_info, list(user = "profesor", admin = FALSE))
  testthat::expect_false(any(grepl("password", names(result$user_info))))
})

testthat::test_that("the shared checker locks after five failures across sessions", {
  clock <- 100
  check <- make_teacher_auth_checker("Test-only-password-123456", "profesor", now = function() clock)
  for (i in seq_len(5)) testthat::expect_false(check("profesor", "incorrect")$result)
  testthat::expect_false(check("profesor", "Test-only-password-123456")$result)
  clock <- 399
  testthat::expect_false(check("profesor", "Test-only-password-123456")$result)
  clock <- 400
  testthat::expect_true(check("profesor", "Test-only-password-123456")$result)
})

testthat::test_that("expiry and logout cannot be revived by input activity or reconnect", {
  clock <- 10
  guard <- make_teacher_session_guard(900, now = function() clock)
  testthat::expect_false(guard$authenticated())
  testthat::expect_false(guard$touch())
  guard$login()
  clock <- 910
  testthat::expect_false(guard$authenticated())
  testthat::expect_false(guard$touch())
  guard$login()
  testthat::expect_true(guard$authenticated())
  guard$logout()
  testthat::expect_false(guard$authenticated())
  testthat::expect_false(make_teacher_session_guard()$authenticated())
})

testthat::test_that("actual login module gates actions after forged inputs, logout and expiry", {
  clock <- 100
  check <- make_teacher_auth_checker("Test-only-password-123456", "profesor")
  shiny::testServer(function(input, output, session) {
    authenticated <- teacher_auth_server(shiny::div("Private panel"), check,
      input, output, session, now = function() clock)
    executed <- shiny::reactiveVal(0L)
    shiny::observeEvent(input$protected_action, {
      shiny::req(authenticated())
      executed(executed() + 1L)
    })
    output$private_value <- shiny::renderText({ shiny::req(authenticated()); "Private" })
  }, {
    session$flushReact()
    session$setInputs(shinymanager_where = "application", result = TRUE, protected_action = 1)
    testthat::expect_equal(executed(), 0L)
    testthat::expect_false(authenticated())
    session$setInputs(`teacher_login-user_id` = "profesor",
      `teacher_login-user_pwd` = "Test-only-password-123456", `teacher_login-go_auth` = 1)
    testthat::expect_true(authenticated())
    session$setInputs(protected_action = 2)
    testthat::expect_equal(executed(), 1L)
    # Logout wins even when a client batches it with a privileged action.
    session$setInputs(teacher_logout = 1, protected_action = 3)
    testthat::expect_false(authenticated())
    testthat::expect_equal(executed(), 1L)
    session$setInputs(shinymanager_where = "application", result = TRUE, protected_action = 4)
    testthat::expect_equal(executed(), 1L)
    session$setInputs(`teacher_login-user_pwd` = "Test-only-password-123456", `teacher_login-go_auth` = 2)
    testthat::expect_true(authenticated())
    clock <<- 1000
    # No periodic timer must be needed to deny the first post-timeout action.
    session$setInputs(protected_action = 5)
    testthat::expect_false(authenticated())
    testthat::expect_equal(executed(), 1L)
  })
})
