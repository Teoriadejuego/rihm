if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]])) {
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
}
library(shiny)
library(bslib)

current_directory <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
project_root <- if (basename(current_directory) == "admin") dirname(current_directory) else current_directory
source(file.path(project_root, "R", "load_all.R"), encoding = "UTF-8")
source_project_modules(project_root)
if (!exists("make_teacher_coordinator", mode = "function")) source(file.path(project_root, "R", "teacher_coordinator.R"), encoding = "UTF-8")
for (module in c("content.R", "layout.R")) source(file.path(project_root, "admin", "modules", module), encoding = "UTF-8")
addResourcePath("teacher-assets", file.path(project_root, "admin", "www"))

cloud_mode <- is_cloud_teacher()
options(shiny.sanitize.errors = TRUE)
auth_setup <- if (cloud_mode) tryCatch(
  list(check = make_teacher_auth_checker(), error = NULL),
  error = function(error) list(check = NULL, error = "Private teacher authentication is not configured.")
) else list(check = NULL, error = NULL)
config_result <- tryCatch(list(value = read_app_config(project_root), error = NULL),
  error = function(error) list(value = NULL, error = "The private server configuration could not be loaded."))

# I(1) forces a separate process instead of future's single-worker sequential
# fallback. This is one compute worker shared by all sessions, not one per user.
future::plan(future::multisession, workers = I(1L))
teacher_coordinator <- make_teacher_coordinator(cooldown_seconds = 180)
teacher_panel_ui <- teacher_panel_layout()
ui <- fluidPage(
  theme = bs_theme(version = 5, primary = "#096b67", bg = "#edf3f6", fg = "#213746"),
  tags$head(tags$link(rel = "stylesheet", href = "teacher-assets/research.css"),
    tags$script(src = "teacher-assets/research.js")),
  if (!is.null(auth_setup$error)) div(class = "research-empty", h2("Teacher setup required"), p(auth_setup$error))
  else if (cloud_mode) uiOutput("teacher_access_ui") else teacher_panel_ui
)

server <- function(input, output, session) {
  authenticated <- if (!cloud_mode) function() TRUE else if (!is.null(auth_setup$error)) function() FALSE
    else teacher_auth_server(teacher_panel_ui, auth_setup$check, input, output, session)
  owner <- session$token
  lifecycle <- new.env(parent = emptyenv())
  lifecycle$alive <- TRUE
  candidate <- reactiveVal(NULL)
  operation_id <- reactiveVal(NULL)
  phase <- reactiveVal(NULL)
  status <- reactiveVal("Ready. The last published group remains available to students.")
  last_activity <- reactiveVal(as.numeric(Sys.time()))
  slide <- reactiveVal(1L)
  presenting <- reactiveVal(FALSE)
  pinned <- reactiveVal(NULL)
  slides <- teacher_slides()

  shared <- reactive({ invalidateLater(1000, session); teacher_coordinator$state() })
  signed_in <- function() lifecycle$alive && isTRUE(isolate(authenticated()))
  clear_private <- function() {
    candidate(NULL)
    presenting(FALSE)
    pinned(NULL)
    teacher_coordinator$cancel(owner)
  }
  session$onSessionEnded(function() {
    lifecycle$alive <- FALSE
    teacher_coordinator$cancel(owner)
  })

  fail_operation <- function(kind, id) {
    message <- if (identical(kind, "publish"))
      "Publication could not be confirmed. Reload the published snapshot before trying again; the student site keeps its last successful deployment."
    else "The operation could not finish. Check the configured connections and try again; the published snapshot was not replaced."
    teacher_coordinator$finish(id, message)
    if (signed_in()) status(message)
    invisible(NULL)
  }

  complete_value <- function(kind, id, value) {
    # Terminal reconciliation is unconditional and synchronous in the main
    # promise callback, before any session observer could be destroyed.
    message <- teacher_finish_public_operation(teacher_coordinator, id, value)
    if (!is.null(message)) {
      if (signed_in()) status(message)
      return(invisible(NULL))
    }
    if (!identical(value$type, "prepared")) stop("Unexpected worker result.")
    state <- teacher_coordinator$state()
    if (!signed_in() || is.null(state$job) || !identical(state$job$id, id) || isTRUE(state$job$cancelled)) {
      teacher_coordinator$finish(id, "The pending candidate was cancelled without publication.")
      if (signed_in()) status("The pending candidate was cancelled without publication.")
      return(invisible(NULL))
    }
    candidate(value$candidate)
    if (isTRUE(value$candidate$demonstration) || identical(kind, "demo")) {
      teacher_coordinator$finish(id, "Private demonstration ready. The student site is unchanged.")
      status("Private demonstration ready in Diagnostics. It cannot be published from this panel.")
      return(invisible(NULL))
    }
    # Main-process auth is rechecked after computation. The permission remains
    # revocable during the following network operation and expires on its own.
    if (!teacher_coordinator$may_publish(id, owner, authenticated())) {
      teacher_coordinator$finish(id, "The candidate is no longer authorised for publication.")
      return(invisible(NULL))
    }
    permission <- tryCatch(teacher_coordinator$grant(id, owner, authenticated(),
      expires_at = last_activity() + 899), error = function(error) NULL)
    if (is.null(permission)) {
      teacher_coordinator$finish(id, "Publication permission expired before the write.")
      status("Publication permission expired. Sign in again before updating.")
      return(invisible(NULL))
    }
    phase("publish")
    status("The protected candidate is ready. Publishing it and checking the student site.")
    # ExtendedTask queues this invocation until its current promise settles.
    # No reactive observer is needed to hand off the still-locked operation.
    operation$invoke("publish", config_result$value, id,
      results = value$candidate$results, permission = permission)
    invisible(NULL)
  }

  operation <- shiny::ExtendedTask$new(function(kind, config, id, results = NULL, permission = NULL) {
    promise <- promises::future_promise({
      if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]])) {
        invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
      }
      source(file.path(config$project_root, "R", "load_all.R"), local = TRUE, encoding = "UTF-8")
      source_project_modules(config$project_root)
      if (!exists("teacher_operation_worker", mode = "function")) source(file.path(config$project_root, "R", "teacher_coordinator.R"), encoding = "UTF-8")
      teacher_operation_worker(kind, config, results, permission)
    }, globals = list(kind = kind, config = config, results = results, permission = permission), seed = TRUE)
    shiny::withReactiveDomain(NULL, promises::then(promise,
      onFulfilled = function(value) {
        tryCatch(shiny::isolate(complete_value(kind, id, value)),
          error = function(error) fail_operation(kind, id))
        list(type = "settled")
      },
      onRejected = function(error) {
        fail_operation(kind, id)
        list(type = "failed")
      }
    ))
  })

  start_operation <- function(kind) {
    req(authenticated())
    if (is.null(config_result$value)) {
      status(config_result$error)
      return(invisible(FALSE))
    }
    id <- tryCatch(teacher_coordinator$begin(owner, kind, authenticated()), error = function(error) error)
    if (inherits(id, "error")) {
      status(conditionMessage(id))
      return(invisible(FALSE))
    }
    operation_id(id)
    phase(kind)
    if (kind %in% c("update", "demo")) candidate(NULL)
    status(if (kind == "update") "Downloading both surveys and preparing the latest group."
      else if (kind == "demo") "Preparing a synthetic preview. This cannot publish to the student site."
      else "Reading the current published snapshot.")
    operation$invoke(kind, config_result$value, id)
    invisible(TRUE)
  }

  observeEvent(authenticated(), {
    if (isTRUE(authenticated())) {
      last_activity(as.numeric(Sys.time()))
      if (!teacher_coordinator$state()$busy) start_operation("refresh")
    } else clear_private()
  }, ignoreNULL = FALSE)
  observe({
    invalidateLater(1000, session)
    if (!isTRUE(authenticated())) clear_private()
  })
  observe({
    reactiveValuesToList(input)
    if (isTRUE(authenticated())) last_activity(as.numeric(Sys.time()))
  }, priority = -1100)

  observeEvent(input$update_publish, start_operation("update"))
  observeEvent(input$refresh_latest, start_operation("refresh"))
  observeEvent(input$load_demo, start_operation("demo"))
  observeEvent(input$cancel_operation, {
    req(authenticated())
    if (teacher_coordinator$cancel(owner)) status("Cancellation requested. An already completed commit will still be reconciled.")
  }, priority = 1500)

  observe({
    req(authenticated())
    state <- shared()
    session$sendCustomMessage("teacher-controls", list(
      update_publish = !state$busy && state$cooldown_remaining == 0L && !is.null(config_result$value),
      refresh_latest = !state$busy, load_demo = !state$busy,
      cancel_operation = state$busy && identical(state$job$owner, owner) && !isTRUE(state$job$cancelled)))
  })

  output$student_link <- renderUI({
    req(authenticated(), config_result$value)
    tags$a(class = "btn btn-outline-primary", href = config_result$value$publication$pages_base_url,
      target = "_blank", rel = "noopener", "Open student dashboard")
  })
  output$connection_status <- renderUI({
    req(authenticated())
    if (!is.null(config_result$error)) return(div(class = "research-notice", config_result$error))
    missing <- c(if (!all(nzchar(Sys.getenv(c("QUALTRICS_API_KEY", "QUALTRICS_BASE_URL"))))) "Qualtrics connection",
      if (!nzchar(Sys.getenv("GITHUB_PUBLICATION_TOKEN"))) "publication connection")
    if (length(missing)) div(class = "research-notice", paste("Server setup required:", paste(missing, collapse = " and ")))
      else p("Private connections are configured on the server. No credentials are requested in this panel.")
  })
  output$operation_status <- renderText({ req(authenticated()); state <- shared(); if (state$busy) state$job$phase else status() })
  output$cooldown_status <- renderText({
    req(authenticated()); remaining <- shared()$cooldown_remaining
    if (remaining > 0L) paste("Next real update in", remaining, "seconds.") else "The shared update cooldown has ended."
  })
  output$latest_summary <- renderUI({ req(authenticated()); teacher_snapshot_summary(shared()$latest) })
  output$latest_bars <- renderUI({ req(authenticated()); teacher_group_bars(shared()$latest) })
  output$latest_behaviours <- renderTable({ req(authenticated()); teacher_table_preview(shared()$latest, "cells") }, striped = TRUE)
  output$latest_matrix <- renderTable({ req(authenticated()); teacher_table_preview(shared()$latest, "matrix_cells") }, striped = TRUE)
  output$candidate_summary <- renderUI({
    req(authenticated()); value <- candidate()
    if (is.null(value)) return(p("No candidate has been prepared in this session."))
    tagList(if (isTRUE(value$demonstration)) div(class = "research-notice", "Synthetic demonstration. Private preview only; not published."),
      teacher_snapshot_summary(value$results, heading = "Prepared candidate"))
  })
  output$quality_diagnostics <- renderTable({ req(authenticated(), candidate()); candidate()$diagnostics }, striped = TRUE)
  output$selection_diagnostics <- renderTable({
    req(authenticated(), candidate()); selection <- candidate()$selection
    if (is.null(selection)) return(NULL)
    data.frame(Selection = names(selection), Value = vapply(selection, function(value) paste(value, collapse = ", "), character(1)))
  }, striped = TRUE)
  output$candidate_behaviours <- renderTable({ req(authenticated(), candidate()); teacher_table_preview(candidate()$results, "cells") }, striped = TRUE)
  output$candidate_matrix <- renderTable({ req(authenticated(), candidate()); teacher_table_preview(candidate()$results, "matrix_cells") }, striped = TRUE)

  move_slide <- function(direction) { req(authenticated()); slide(max(1L, min(length(slides), slide() + direction))) }
  observeEvent(input$slide_previous, move_slide(-1L))
  observeEvent(input$slide_next, move_slide(1L))
  observeEvent(input$slide_key, { req(authenticated()); if (input$slide_key$direction %in% c(-1, 1)) move_slide(input$slide_key$direction) })
  observeEvent(input$slide_jump, { req(authenticated()); if (input$slide_jump$slide %in% c(1, 12)) slide(input$slide_jump$slide) })
  observeEvent(input$presentation_started, {
    req(authenticated()); if (!presenting()) pinned(teacher_coordinator$state()$latest); presenting(TRUE)
  })
  observeEvent(input$presentation_exited, { req(authenticated()); presenting(FALSE); pinned(NULL) })
  observeEvent(input$stop_presentation, {
    req(authenticated()); presenting(FALSE); pinned(NULL); session$sendCustomMessage("teacher-exit-fullscreen", list())
  })
  projected <- reactive({ req(authenticated()); if (presenting()) pinned() else shared()$latest })
  output$slide_position <- renderUI({ req(authenticated()); span(paste("Slide", slide(), "of", length(slides))) })
  output$projection_slide <- renderUI({
    req(authenticated()); item <- slides[[slide()]]
    tagList(h2(item$title), if (slide() == 9L) tagList(teacher_snapshot_summary(projected()), teacher_group_bars(projected())) else item$content)
  })
  output$presenter_notes <- renderText({ req(authenticated()); slides[[slide()]]$notes })
  output$presentation_snapshot <- renderText({
    req(authenticated()); value <- projected()
    paste(if (presenting()) "Pinned publication:" else "Publication:",
      if (is.null(value)) "none available" else value$metadata$publication_id)
  })
}

shinyApp(ui, server)
