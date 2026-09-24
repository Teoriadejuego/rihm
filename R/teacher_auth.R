is_cloud_teacher <- function() identical(Sys.getenv("TEACHER_HOST_MODE"), "cloud")

# One checker is shared by sessions in this R process. Reconnecting does not
# reset its failed-login limit. The managed host supplies HTTPS in production.
make_teacher_auth_checker <- function(password = Sys.getenv("TEACHER_PASSWORD"),
                                      username = Sys.getenv("TEACHER_USERNAME", "profesor"),
                                      now = function() as.numeric(Sys.time())) {
  if (!is.character(password) || length(password) != 1L || is.na(password) || nchar(password) < 20L ||
      !is.character(username) || length(username) != 1L || is.na(username) || !nzchar(username)) {
    stop("Set TEACHER_USERNAME and a TEACHER_PASSWORD of at least 20 characters in the host's secret settings.", call. = FALSE)
  }
  hash <- sodium::password_store(password)
  password <- NULL
  failures <- 0L
  locked_until <- 0
  function(user, password) {
    failed <- list(result = FALSE, user_info = NULL)
    current <- now()
    if (current < locked_until) return(failed)
    if (locked_until > 0) {
      failures <<- 0L
      locked_until <<- 0
    }
    valid <- is.character(user) && length(user) == 1L && !is.na(user) &&
      is.character(password) && length(password) == 1L && !is.na(password) &&
      nchar(user, type = "bytes") <= 256L && nchar(password, type = "bytes") <= 1024L &&
      isTRUE(tryCatch(sodium::password_verify(hash, password), error = function(e) FALSE)) &&
      identical(user, username)
    if (!valid) {
      failures <<- failures + 1L
      if (failures >= 5L) locked_until <<- current + 300
      return(failed)
    }
    failures <<- 0L
    list(result = TRUE, user_info = list(user = username, admin = FALSE))
  }
}

# Authentication belongs to one live Shiny session. No browser input, URL token,
# or cached reactive result can revive a logged-out or expired session.
make_teacher_session_guard <- function(timeout_seconds = 900,
                                       now = function() as.numeric(Sys.time())) {
  signed_in <- FALSE
  last_activity <- -Inf
  logout <- function() { signed_in <<- FALSE; invisible(FALSE) }
  valid <- function() {
    if (!signed_in) return(FALSE)
    if (now() - last_activity >= timeout_seconds) return(logout())
    TRUE
  }
  list(
    login = function() { last_activity <<- now(); signed_in <<- TRUE; invisible(TRUE) },
    authenticated = valid,
    touch = function() {
      if (!valid()) return(invisible(FALSE))
      last_activity <<- now()
      invisible(TRUE)
    },
    logout = logout
  )
}

# Public shinymanager modules handle only the login form and password check.
# This layer owns authorization, expiry and logout, without URL bearer tokens.
teacher_auth_server <- function(panel_ui, check_credentials, input, output, session,
                                timeout_seconds = 900,
                                now = function() as.numeric(Sys.time())) {
  guard <- make_teacher_session_guard(timeout_seconds, now)
  revision <- shiny::reactiveVal(0L)
  auth <- shiny::callModule(shinymanager::auth_server, "teacher_login",
    check_credentials = check_credentials, use_token = FALSE)
  session$allowReconnect(FALSE)
  session$onSessionEnded(guard$logout)

  invalidate_auth <- function() revision(shiny::isolate(revision()) + 1L)
  close_access <- function() {
    guard$logout()
    auth$result <- FALSE
    auth$user <- NULL
    auth$user_info <- NULL
    invalidate_auth()
  }
  authenticated <- function() {
    revision()
    # Deliberately a function, not a reactive: every action checks the clock.
    guard$authenticated()
  }
  shiny::observeEvent(auth$result, {
    if (isTRUE(auth$result) && is.list(auth$user_info) &&
        identical(auth$user, auth$user_info$user)) {
      guard$login()
      invalidate_auth()
      shiny::updateTextInput(session, "teacher_login-user_pwd", value = "")
    }
  }, ignoreInit = FALSE, priority = 1000)
  shiny::observeEvent(input$teacher_logout, close_access(),
    ignoreInit = TRUE, priority = 2000)
  shiny::observe({
    shiny::invalidateLater(10000, session)
    if (isTRUE(shiny::isolate(auth$result)) && !guard$authenticated()) close_access()
  })
  shiny::observe({
    shiny::reactiveValuesToList(input)
    guard$touch()
  }, priority = -1000)
  output$teacher_access_ui <- shiny::renderUI({
    if (authenticated()) {
      shiny::tagList(
        shiny::div(style = "padding: 10px; text-align: right;",
          shiny::actionButton("teacher_logout", "Cerrar sesión")),
        panel_ui
      )
    } else {
      shinymanager::auth_ui("teacher_login", choose_language = "es")
    }
  })
  authenticated
}
