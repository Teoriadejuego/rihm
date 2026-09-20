library(shiny)
library(bslib)

current_directory <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
project_root <- if (basename(current_directory) == "admin") dirname(current_directory) else current_directory
source(file.path(project_root, "R", "load_all.R"))
source_project_modules(project_root)

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
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("1. Download and validate"),
        textInput("session_code", "Class session code", placeholder = "Enter the code used by students"),
        actionButton("download", "Download once from Qualtrics", class = "btn-primary w-100"),
        hr(),
        checkboxInput(
          "confirm",
          "I have reviewed the diagnostics and aggregate preview.",
          value = FALSE
        ),
        actionButton("validate_local", "Validate and render locally", class = "btn-outline-primary w-100"),
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

server <- function(input, output, session) {
  candidate <- reactiveVal(NULL)
  status <- reactiveVal("No publication has been attempted in this session.")

  refresh_snapshot_input <- function() {
    updateSelectInput(session, "snapshot", choices = snapshot_choices(project_root))
  }
  refresh_snapshot_input()

  output$configuration_status <- renderUI({
    if (!is.null(config_result$error)) {
      div(class = "alert alert-danger", config_result$error)
    } else {
      config <- config_result$value
      pages <- config$publication$pages_base_url
      div(
        class = "status-box",
        strong("Configuration loaded. "),
        if (nzchar(pages)) paste("Pages URL:", pages) else "GitHub Pages URL still needs to be set in config/config.yml."
      )
    }
  })

  observeEvent(input$download, {
    req(config_result$value)
    code <- trimws(input$session_code)
    if (!nzchar(code)) {
      showNotification("Enter a class session code first.", type = "error")
      return()
    }
    candidate(NULL)
    status("Downloading both surveys and validating the selected class session …")
    result <- tryCatch(
      withProgress(message = "Downloading from Qualtrics once", value = 0.1, {
        downloaded <- download_surveys_once(config_result$value)
        incProgress(0.45, detail = "Normalising and classifying responses")
        value <- prepare_publication_candidate(downloaded, code, config_result$value)
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
      showNotification("Download complete. Review the diagnostics and public preview.", type = "message")
    }
  })

  output$candidate_summary <- renderUI({
    value <- candidate()
    if (is.null(value)) return(div(class = "alert alert-secondary", "No candidate loaded."))
    cells <- value$results$cells
    div(
      class = "alert alert-info",
      tags$b(value$results$metadata$publication_id), tags$br(),
      paste(sum(!cells$suppressed), "visible behaviour cells and", sum(cells$suppressed), "suppressed cells."),
      tags$br(),
      "Indicators overlap by design; their percentages are not a mutually exclusive distribution."
    )
  })

  output$diagnostics <- renderTable({
    req(candidate())
    format_diagnostics(candidate())
  }, striped = TRUE, bordered = FALSE, spacing = "s")

  output$public_preview <- renderTable({
    req(candidate())
    preview <- candidate()$results$cells
    preview$count <- ifelse(preview$suppressed, "Suppressed", as.character(preview$count))
    preview$percentage <- ifelse(preview$suppressed, "Suppressed", paste0(preview$percentage, "%"))
    preview[c("scope", "country", "gender", "behaviour", "count", "percentage", "denominator_type")]
  }, striped = TRUE, bordered = FALSE, spacing = "xs")

  perform_publication <- function(results, session_code = character(), push = TRUE) {
    if (!isTRUE(input$confirm)) {
      showNotification("Confirm that you reviewed the candidate first.", type = "warning")
      return(NULL)
    }
    label <- if (push) "Publishing and waiting for GitHub Pages" else "Running local validation"
    status(paste0(label, " …"))
    result <- tryCatch(
      withProgress(message = label, value = 0.05, {
        publish_results(
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
    req(candidate(), config_result$value)
    perform_publication(candidate()$results, input$session_code, push = FALSE)
  })

  observeEvent(input$publish, {
    req(candidate(), config_result$value)
    perform_publication(candidate()$results, input$session_code, push = TRUE)
  })

  observeEvent(input$refresh_snapshots, refresh_snapshot_input())

  observeEvent(input$rollback, {
    req(config_result$value)
    if (!nzchar(input$snapshot)) {
      showNotification("Select a snapshot first.", type = "warning")
      return()
    }
    rolled_back <- tryCatch(
      prepare_rollback(read_public_snapshot(input$snapshot)),
      error = function(error) error
    )
    if (inherits(rolled_back, "error")) {
      showNotification(conditionMessage(rolled_back), type = "error")
      return()
    }
    perform_publication(rolled_back, push = TRUE)
  })

  output$publication_status <- renderText(status())
}

shinyApp(ui, server)
