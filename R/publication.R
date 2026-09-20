run_checked_command <- function(command, args = character(), working_directory = ".") {
  old <- setwd(working_directory)
  on.exit(setwd(old), add = TRUE)
  output <- suppressWarnings(system2(command, args = args, stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (status != 0L) {
    stop(
      command, " failed with status ", status, ":\n", paste(output, collapse = "\n"),
      call. = FALSE
    )
  }
  output
}

assert_git_repository <- function(project_root) {
  output <- run_checked_command("git", c("rev-parse", "--show-toplevel"), project_root)
  repository <- normalizePath(output[[1L]], winslash = "/", mustWork = TRUE)
  root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  if (!identical(tolower(repository), tolower(root))) {
    stop("publication.repo_root must be the Git repository root.", call. = FALSE)
  }
  invisible(TRUE)
}

run_project_tests <- function(project_root) {
  run_checked_command("Rscript", "scripts/run_tests.R", project_root)
}

render_student_site <- function(project_root) {
  if (!nzchar(Sys.which("quarto"))) stop("Quarto is not installed or is not on PATH.", call. = FALSE)
  run_checked_command(
    "quarto",
    c("render", "student/index.qmd", "--output-dir", "_site"),
    project_root
  )
}

scan_public_files <- function(project_root, secrets = character()) {
  roots <- c(
    file.path(project_root, "student", "data"),
    file.path(project_root, "student", "_site")
  )
  files <- unlist(lapply(roots[file.exists(roots)], function(root) {
    list.files(root, recursive = TRUE, full.names = TRUE)
  }), use.names = FALSE)
  text_extensions <- c("json", "html", "js", "css", "xml", "txt", "csv")
  files <- files[tolower(tools::file_ext(files)) %in% text_extensions]
  if (!length(files)) stop("No public files were found to scan.", call. = FALSE)

  forbidden <- c(
    "session_password", "session_code", "responseid", "recipientemail",
    "recipientfirstname", "recipientlastname", "ipaddress", "qualtrics_api_key"
  )
  findings <- character()
  for (file in files) {
    bytes <- readBin(file, what = "raw", n = file.info(file)$size)
    content <- iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
    lower <- tolower(content)
    hits <- forbidden[vapply(forbidden, grepl, logical(1), x = lower, fixed = TRUE)]
    secret_hits <- secrets[
      !is.na(secrets) & nzchar(secrets) &
        vapply(secrets, grepl, logical(1), x = content, fixed = TRUE)
    ]
    if (length(hits) || length(secret_hits)) {
      findings <- c(findings, paste(basename(file), paste(c(hits, "private-value"[length(secret_hits) > 0]), collapse = ", ")))
    }
  }
  if (length(findings)) {
    stop("Privacy scan failed: ", paste(findings, collapse = "; "), call. = FALSE)
  }
  invisible(files)
}

commit_and_push_publication <- function(project_root, publication_id, branch = "main") {
  assert_git_repository(project_root)
  paths <- c("student/data/public_results.json", "student/data/public_manifest.json")
  run_checked_command("git", c("add", "--", paths), project_root)
  staged <- run_checked_command("git", c("diff", "--cached", "--name-only"), project_root)
  expected_message <- paste0("Publish classroom results ", publication_id)
  if (length(staged)) {
    run_checked_command(
      "git",
      c("commit", "-m", expected_message, "--", paths),
      project_root
    )
  } else {
    last_message <- run_checked_command("git", c("log", "-1", "--format=%s"), project_root)
    if (!length(last_message) || !identical(last_message[[1L]], expected_message)) {
      stop("There are no public data changes to publish and HEAD is not this publication.", call. = FALSE)
    }
  }
  run_checked_command("git", c("push", "origin", branch), project_root)
  invisible(if (length(staged)) staged else paths)
}

verify_deployment <- function(base_url, publication_id, timeout_seconds = 180L, poll_seconds = 5L) {
  if (!nzchar(base_url)) {
    return(list(verified = FALSE, message = "No Pages base URL is configured; deployment was pushed but not verified."))
  }
  url <- paste0(sub("/+$", "", base_url), "/data/public_manifest.json")
  deadline <- Sys.time() + as.numeric(timeout_seconds)
  last_error <- NULL
  while (Sys.time() < deadline) {
    candidate <- paste0(url, "?cache=", as.integer(Sys.time()))
    manifest <- tryCatch(
      jsonlite::read_json(candidate, simplifyVector = TRUE),
      error = function(error) {
        last_error <<- conditionMessage(error)
        NULL
      }
    )
    if (!is.null(manifest) && identical(as.character(manifest$publication_id), publication_id)) {
      return(list(verified = TRUE, message = paste("GitHub Pages serves", publication_id)))
    }
    Sys.sleep(poll_seconds)
  }
  list(
    verified = FALSE,
    message = paste0("Timed out waiting for GitHub Pages.", if (!is.null(last_error)) paste0(" Last error: ", last_error) else "")
  )
}

publish_results <- function(results, config, secrets = character(), push = TRUE, verify = TRUE) {
  project_root <- config$project_root
  if (push) assert_git_repository(project_root)
  write_public_snapshot(results, project_root, secrets = secrets, save_snapshot = TRUE)
  test_output <- run_project_tests(project_root)
  render_output <- render_student_site(project_root)
  scanned <- scan_public_files(project_root, secrets = secrets)

  if (push) {
    commit_and_push_publication(
      project_root,
      results$metadata$publication_id,
      config$publication$branch
    )
  }
  deployment <- if (push && verify) {
    verify_deployment(
      config$publication$pages_base_url %||% "",
      results$metadata$publication_id,
      config$publication$verify_timeout_seconds %||% 180L
    )
  } else {
    list(verified = FALSE, message = if (push) "Verification skipped." else "Local validation only; no push requested.")
  }
  list(
    publication_id = results$metadata$publication_id,
    tests = test_output,
    render = render_output,
    scanned_files = length(scanned),
    deployment = deployment
  )
}

`%||%` <- function(x, fallback) if (is.null(x)) fallback else x
