library(shiny)
library(bslib)

current_directory <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
project_root <- if (basename(current_directory) == "admin") dirname(current_directory) else current_directory
source(file.path(project_root, "R", "load_all.R"))
source_project_modules(project_root)
cloud_mode <- is_cloud_teacher()
auth_setup <- if (cloud_mode) tryCatch(
  list(check = make_teacher_auth_checker(), error = NULL),
  error = function(error) list(check = NULL, error = conditionMessage(error))
) else list(check = NULL, error = NULL)

config_result <- tryCatch(
  list(value = read_app_config(project_root), error = NULL),
  error = function(error) list(value = NULL, error = conditionMessage(error))
)

format_diagnostics <- function(candidate) {
  class <- transform(candidate$class$diagnostics, Scope = "Class")
  reference <- transform(candidate$reference$diagnostics, Scope = "International")
  result <- rbind(class, reference)
  result[c("Scope", "metric", "value")]
}

snapshot_choices <- function(root) {
  files <- list.files(file.path(root, "snapshots"), pattern = "\\.json$", full.names = TRUE)
  if (!length(files)) return(character())
  stats <- file.info(files)
  files <- files[order(stats$mtime, decreasing = TRUE)]
  stats::setNames(files, sub("\\.json$", "", basename(files)))
}

ui <- page_fillable(
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = "#1B6EC2"),
  tags$head(tags$style(HTML("
    body { background: #f4f8fd; }
    .navbar { box-shadow: 0 3px 15px rgba(11,61,145,.12); }
    .card { border: 1px solid #dfe9f7; box-shadow: 0 2px 10px rgba(11,61,145,.06); }
    .status-box { padding: 12px 14px; border-radius: 10px; background: #eef5ff; }
    .privacy-note { color: #526071; font-size: .92rem; }
  "))),
  layout_column_wrap(
    width = 1,
    heights_equal = "row",
    card(
      card_header("Mini-dictator classroom publisher"),
      p(
        "Download once from Qualtrics, inspect the aggregate preview, and publish a static classroom snapshot.",
        class = "privacy-note"
      ),
      uiOutput("configuration_status")
    ),
    if (cloud_mode) card(
      card_header("Conexiones privadas de esta sesión"),
      p("Para probar, selecciona Demonstration y usa DEMO-RIHM. Para datos reales, introduce tus credenciales de Qualtrics. Para publicar, añade un token de GitHub limitado al repositorio Teoriadejuego/rihm con Contents: Read and write. Estos campos no se guardan en GitHub ni entre sesiones.", class = "privacy-note"),
      layout_columns(
        passwordInput("github_token", "Token de GitHub para publicar"),
        passwordInput("qualtrics_api_key", "Clave API de Qualtrics"),
        textInput("qualtrics_base_url", "Servidor de Qualtrics", placeholder = "centro-de-datos.qualtrics.com"),
        col_widths = c(4, 4, 4)
      )
    ),
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("1. Download and validate"),
        radioButtons("data_source", "Data source", choices = c(
          "Qualtrics: real responses" = "qualtrics",
          "Demonstration: synthetic responses" = "demo"
        )),
        textInput("session_code", "Class session code", placeholder = "Enter the code used by students"),
        actionButton("download", "Download once from Qualtrics", class = "btn-primary w-100"),
        conditionalPanel(
          condition = "input.data_source === 'demo'",
          p("DEMONSTRATION ONLY. Generated test data; no real participants or Qualtrics connection.", class = "alert alert-warning")
        ),
        hr(),
        checkboxInput(
          "confirm",
          "I have reviewed the diagnostics and aggregate preview.",
          value = FALSE
        ),
        actionButton("validate_local", if (cloud_mode) "Validate aggregate data" else "Validate and render locally", class = "btn-outline-primary w-100"),
        br(), br(),
        actionButton("publish", "Publish to GitHub Pages", class = "btn-success w-100"),
        hr(),
        selectInput("snapshot", "Previous public snapshot", choices = character()),
        actionButton("refresh_snapshots", "Refresh snapshot list", class = "btn-outline-secondary"),
        actionButton("rollback", "Republish selected snapshot", class = "btn-warning")
      ),
      card(
        card_header("2. Review"),
        uiOutput("candidate_summary"),
        h5("Private validation diagnostics"),
        tableOutput("diagnostics"),
        h5("Exact public behaviour cells"),
        div(style = "max-height: 390px; overflow-y: auto;", tableOutput("public_preview"))
      )
    ),
    card(
      card_header("3. Publication status"),
      verbatimTextOutput("publication_status", placeholder = TRUE)
    )
  )
)

if (cloud_mode) {
  options(shiny.sanitize.errors = TRUE)
  teacher_panel_ui <- ui
  ui <- if (!is.null(auth_setup$error)) {
    fluidPage(h2("Teacher panel setup required"), p(auth_setup$error))
  } else fluidPage(uiOutput("teacher_access_ui"))
}

server <- function(input, output, session) {
  authenticated <- if (!cloud_mode) function() TRUE else if (!is.null(auth_setup$error)) {
    function() FALSE
  } else teacher_auth_server(teacher_panel_ui, auth_setup$check, input, output, session)
  candidate <- reactiveVal(NULL)
  status <- reactiveVal("No publication has been attempted in this session.")
  github_token <- function() {
    req(authenticated())
    supplied <- input$github_token
    if (is.character(supplied) && nzchar(trimws(supplied))) trimws(supplied) else Sys.getenv("GITHUB_PUBLICATION_TOKEN")
  }

  refresh_snapshot_input <- function() {
    req(authenticated())
    choices <- if (cloud_mode) {
      if (!nzchar(github_token())) return(invisible(NULL))
      tryCatch({
        history <- list_github_snapshots(config_result$value, token = github_token())
        stats::setNames(history$ref, history$label)
      }, error = function(error) {
        status(conditionMessage(error))
        character()
      })
    } else snapshot_choices(project_root)
    updateSelectInput(session, "snapshot", choices = choices)
  }
  observeEvent(authenticated(), {
    if (isTRUE(authenticated())) refresh_snapshot_input() else {
      candidate(NULL)
      status("No publication has been attempted in this session.")
      for (field in c("github_token", "qualtrics_api_key", "qualtrics_base_url", "session_code")) {
        updateTextInput(session, field, value = "")
      }
    }
  }, ignoreNULL = FALSE)

  observeEvent(input$data_source, {
    req(authenticated())
    candidate(NULL)
    updateCheckboxInput(session, "confirm", value = FALSE)
    is_demo <- identical(input$data_source, "demo")
    updateTextInput(session, "session_code", value = if (is_demo) demo_session_code() else "")
    updateActionButton(session, "download", label = if (is_demo) "Load demonstration" else "Download once from Qualtrics")
  })

  output$configuration_status <- renderUI({
    req(authenticated())
    if (!is.null(config_result$error)) {
      div(class = "alert alert-danger", config_result$error)
    } else {
      config <- config_result$value
      pages <- config$publication$pages_base_url
      div(
        class = "status-box",
        strong("Configuration loaded. "),
        if (nzchar(pages)) tags$a("Open student dashboard", href = pages, target = "_blank", rel = "noopener") else "GitHub Pages URL still needs to be set in config/config.yml."
      )
    }
  })

  observeEvent(input$download, {
    req(authenticated(), config_result$value)
    code <- trimws(input$session_code)
    if (!nzchar(code)) {
      showNotification("Enter a class session code first.", type = "error")
      return()
    }
    candidate(NULL)
    is_demo <- identical(input$data_source, "demo")
    status(if (is_demo) "Preparing explicitly synthetic demonstration data …" else "Downloading both surveys and validating the selected class session …")
    result <- tryCatch(
      withProgress(message = if (is_demo) "Loading synthetic demonstration" else "Downloading from Qualtrics once", value = 0.1, {
        value <- if (is_demo) {
          prepare_demo_candidate(config_result$value, code)
        } else {
          credentials <- if (cloud_mode) list(
            api_key = input$qualtrics_api_key,
            base_url = input$qualtrics_base_url
          ) else NULL
          downloaded <- download_surveys_once(config_result$value, credentials = credentials)
          incProgress(0.45, detail = "Normalising and classifying responses")
          prepare_publication_candidate(downloaded, code, config_result$value)
        }
        incProgress(0.45, detail = "Applying privacy suppression")
        value
      }),
      error = function(error) error
    )
    if (inherits(result, "error")) {
      status(paste("Download or validation failed:\n", conditionMessage(result)))
      showNotification(conditionMessage(result), type = "error", duration = NULL)
    } else {
      candidate(result)
      updateCheckboxInput(session, "confirm", value = FALSE)
      status(paste("Candidate", result$results$metadata$publication_id, "is ready for review."))
      showNotification("Candidate ready. Review the diagnostics and public preview.", type = "message")
    }
  })

  output$candidate_summary <- renderUI({
    req(authenticated())
    value <- candidate()
    if (is.null(value)) return(div(class = "alert alert-secondary", "No candidate loaded."))
    cells <- value$results$cells
    div(
      class = "alert alert-info",
      if (identical(value$results$metadata$data_mode, "demonstration")) tags$p(tags$strong("DEMONSTRATION — synthetic data, not real survey results.")),
      tags$b(value$results$metadata$publication_id), tags$br(),
      paste(sum(!cells$suppressed), "visible behaviour cells and", sum(cells$suppressed), "suppressed cells."),
      tags$br(),
      "Indicators overlap by design; their percentages are not a mutually exclusive distribution."
    )
  })

  output$diagnostics <- renderTable({
    req(authenticated(), candidate())
    format_diagnostics(candidate())
  }, striped = TRUE, bordered = FALSE, spacing = "s")

  output$public_preview <- renderTable({
    req(authenticated(), candidate())
    preview <- candidate()$results$cells
    preview$count <- ifelse(preview$suppressed, "Suppressed", as.character(preview$count))
    preview$percentage <- ifelse(preview$suppressed, "Suppressed", paste0(preview$percentage, "%"))
    preview[c("scope", "country", "gender", "behaviour", "count", "percentage", "denominator_type")]
  }, striped = TRUE, bordered = FALSE, spacing = "xs")

  perform_publication <- function(results, session_code = character(), push = TRUE) {
    req(authenticated())
    if (!isTRUE(input$confirm)) {
      showNotification("Confirm that you reviewed the candidate first.", type = "warning")
      return(NULL)
    }
    label <- if (push) "Publishing and waiting for GitHub Pages" else "Running local validation"
    status(paste0(label, " …"))
    result <- tryCatch(
      withProgress(message = label, value = 0.05, {
        if (cloud_mode && push) publish_results_github(
          results, config_result$value, secrets = session_code, token = github_token(), verify = TRUE
        ) else if (cloud_mode) {
          validate_github_public_results(results, secrets = session_code)
          list(publication_id = results$metadata$publication_id, scanned_files = 2L,
               deployment = list(message = "Aggregate data validated. Tests, rendering and artifact scanning run on GitHub when published."))
        } else publish_results(
          results,
          config_result$value,
          secrets = session_code,
          push = push,
          verify = push
        )
      }),
      error = function(error) error
    )
    if (inherits(result, "error")) {
      status(paste(label, "failed:\n", conditionMessage(result)))
      showNotification(conditionMessage(result), type = "error", duration = NULL)
      return(NULL)
    }
    status(paste(
      "Publication:", result$publication_id,
      "\nPrivacy scan:", result$scanned_files, "public files checked",
      "\nDeployment:", result$deployment$message
    ))
    refresh_snapshot_input()
    showNotification(if (push) "Publication workflow completed." else "Local validation completed.", type = "message")
    result
  }

  observeEvent(input$validate_local, {
    req(authenticated(), candidate(), config_result$value)
    perform_publication(candidate()$results, input$session_code, push = FALSE)
  })

  observeEvent(input$publish, {
    req(authenticated(), candidate(), config_result$value)
    perform_publication(candidate()$results, input$session_code, push = TRUE)
  })

  observeEvent(input$refresh_snapshots, refresh_snapshot_input())

  observeEvent(input$rollback, {
    req(authenticated(), config_result$value)
    if (!nzchar(input$snapshot)) {
      showNotification("Select a snapshot first.", type = "warning")
      return()
    }
    rolled_back <- tryCatch(
      prepare_rollback(if (cloud_mode) read_github_snapshot(input$snapshot, config_result$value, token = github_token()) else read_public_snapshot(input$snapshot)),
      error = function(error) error
    )
    if (inherits(rolled_back, "error")) {
      showNotification(conditionMessage(rolled_back), type = "error")
      return()
    }
    perform_publication(rolled_back, push = TRUE)
  })

  output$publication_status <- renderText({ req(authenticated()); status() })
}

shinyApp(ui, server)
