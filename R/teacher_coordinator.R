# A single coordinator is created by admin/app.R and shared by every session
# in that R process. The hosted app must run with one Shiny worker.
make_teacher_coordinator <- function(cooldown_seconds = 180,
                                     now = function() as.numeric(Sys.time()),
                                     on_change = function(state) invisible(NULL)) {
  stopifnot(is.numeric(cooldown_seconds), length(cooldown_seconds) == 1L,
    is.finite(cooldown_seconds), cooldown_seconds >= 0, is.function(on_change))
  next_update <- now() + cooldown_seconds
  job <- NULL
  latest <- NULL
  committed <- NULL
  last_outcome <- "No update has run in this server process."
  sequence <- 0L
  confirmed_revision <- 0L
  state <- function() list(
    busy = !is.null(job), job = job, latest = latest, committed = committed, last_outcome = last_outcome,
    next_update_at = next_update, confirmed_revision = confirmed_revision,
    cooldown_remaining = max(0L, as.integer(ceiling(next_update - now())))
  )
  # Notification failure must never prevent cleanup or strand the shared lock.
  notify <- function() tryCatch(on_change(state()), error = function(error) invisible(NULL))
  matches <- function(id) !is.null(job) && identical(job$id, id)
  revoke <- function() {
    if (!is.null(job$permission)) teacher_revoke_permission(job$permission)
    if (!is.null(job$cancellation)) teacher_revoke_permission(job$cancellation)
  }
  list(
    state = state,
    begin = function(owner, kind, authenticated, expires_at = now() + 899) {
      if (!isTRUE(authenticated)) stop("Sign in before starting an operation.", call. = FALSE)
      if (!kind %in% c("update", "refresh", "demo")) stop("Unknown teacher operation.", call. = FALSE)
      if (!is.null(job)) stop("Another operation is running. Wait for it to finish.", call. = FALSE)
      if (kind == "update" && now() < next_update) {
        stop("The shared three-minute update cooldown is still active.", call. = FALSE)
      }
      if (!is.numeric(expires_at) || length(expires_at) != 1L || !is.finite(expires_at) || expires_at <= now()) {
        stop("The operation permission has expired.", call. = FALSE)
      }
      sequence <<- sequence + 1L
      id <- paste0("job-", sequence)
      cancellation <- teacher_create_permission(id, expires_at)
      if (kind == "update") next_update <<- now() + cooldown_seconds
      job <<- list(id = id, owner = owner, kind = kind,
        phase = if (kind == "update") "Preparing the latest group" else if (kind == "demo") "Preparing a private demonstration" else "Reading the published snapshot",
        cancelled = FALSE, permission = NULL, cancellation = cancellation)
      notify()
      job$id
    },
    cancellation = function(id, owner) {
      if (!matches(id) || !identical(job$owner, owner)) return(NULL)
      job$cancellation
    },
    may_publish = function(id, owner, authenticated) {
      isTRUE(authenticated) && matches(id) && identical(job$owner, owner) &&
        identical(job$kind, "update") && !isTRUE(job$cancelled)
    },
    grant = function(id, owner, authenticated, expires_at) {
      if (!isTRUE(authenticated) || !matches(id) || !identical(job$owner, owner) ||
          job$kind != "update" || isTRUE(job$cancelled) || expires_at <= now()) {
        stop("This operation is no longer authorised to publish.", call. = FALSE)
      }
      if (!is.null(job$permission)) teacher_revoke_permission(job$permission)
      job$permission <<- teacher_create_permission(id, expires_at)
      job$phase <<- "Publishing and checking the student site"
      notify()
      job$permission
    },
    cancel = function(owner) {
      if (is.null(job) || !identical(job$owner, owner)) return(invisible(FALSE))
      if (isTRUE(job$cancelled)) return(invisible(TRUE))
      revoke()
      job$cancelled <<- TRUE
      job$phase <<- "Cancellation requested; waiting for the running operation"
      notify()
      invisible(TRUE)
    },
    finish = function(id, outcome, published = NULL, saved = NULL) {
      if (!matches(id)) return(invisible(FALSE))
      revoke()
      # A completed commit is reconciled even if its originating session ended.
      if (!is.null(published)) {
        latest <<- published
        confirmed_revision <<- confirmed_revision + 1L
      }
      if (!is.null(saved)) committed <<- saved
      last_outcome <<- outcome
      job <<- NULL
      notify()
      invisible(TRUE)
    }
  )
}

# One process-wide adapter; it captures no browser session. reactiveVal's
# identical-value check keeps an unchanged snapshot out of the render graph.
make_teacher_reactive_coordinator <- function(cooldown_seconds = 180,
                                              now = function() as.numeric(Sys.time())) {
  stable <- shiny::reactiveVal(NULL)
  snapshot <- shiny::reactiveVal(NULL)
  coordinator <- make_teacher_coordinator(cooldown_seconds, now, on_change = function(state) {
    stable(state)
    snapshot(state$latest)
  })
  stable(coordinator$state())
  list(coordinator = coordinator, state = stable, snapshot = snapshot,
    cooldown = function(session) shiny::reactive({
      remaining <- max(0L, as.integer(ceiling(stable()$next_update_at - now())))
      if (remaining > 0L) shiny::invalidateLater(1000, session)
      remaining
    }))
}

teacher_control_state <- function(state, cooldown_remaining, owner, configured = TRUE) list(
  update_publish = !state$busy && cooldown_remaining == 0L && isTRUE(configured),
  refresh_latest = !state$busy, load_demo = !state$busy,
  cancel_operation = state$busy && identical(state$job$owner, owner) && !isTRUE(state$job$cancelled)
)

make_teacher_control_sender <- function(send) {
  previous <- NULL
  function(controls = NULL, reset = FALSE) {
    if (isTRUE(reset)) {
      previous <<- NULL
      return(invisible(FALSE))
    }
    if (identical(previous, controls)) return(invisible(FALSE))
    send("teacher-controls", controls)
    previous <<- controls
    invisible(TRUE)
  }
}

teacher_restore_action <- function(pending, authenticated, state, requested_revision) {
  if (!isTRUE(pending) || !isTRUE(authenticated)) return("none")
  if (!is.null(state$latest) && state$confirmed_revision > requested_revision) return("reuse")
  if (isTRUE(state$busy)) return("wait")
  "refresh"
}

# This ephemeral permit contains only a job number and an absolute expiry.
# It is deliberately not a bearer credential and never contains survey data.
teacher_create_permission <- function(job_id, expires_at) {
  if (!is.character(job_id) || length(job_id) != 1L || !grepl("^job-[0-9]+$", job_id) ||
      !is.numeric(expires_at) || length(expires_at) != 1L || !is.finite(expires_at)) {
    stop("Invalid publication permission.", call. = FALSE)
  }
  path <- tempfile("teacher-permission-", fileext = ".rds")
  saveRDS(list(job_id = job_id, expires_at = expires_at), path)
  suppressWarnings(Sys.chmod(path, mode = "0600"))
  list(path = path, job_id = job_id)
}

teacher_permission_valid <- function(permission, now = as.numeric(Sys.time())) {
  if (!is.list(permission) || !is.character(permission$path) || length(permission$path) != 1L ||
      !file.exists(permission$path)) return(FALSE)
  value <- tryCatch(suppressWarnings(readRDS(permission$path)), error = function(error) NULL)
  is.list(value) && identical(value$job_id, permission$job_id) &&
    is.numeric(value$expires_at) && length(value$expires_at) == 1L &&
    is.finite(value$expires_at) && now < value$expires_at
}

teacher_revoke_permission <- function(permission) {
  if (is.list(permission) && is.character(permission$path) && length(permission$path) == 1L) {
    # Only a file generated by this module can be removed; never recurse.
    root <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    parent <- normalizePath(dirname(permission$path), winslash = "/", mustWork = FALSE)
    if (identical(tolower(root), tolower(parent)) &&
        grepl("^teacher-permission-[A-Za-z0-9]+\\.rds$", basename(permission$path))) {
      unlink(permission$path, recursive = FALSE)
    }
  }
  invisible(TRUE)
}

teacher_candidate_preview <- function(candidate) {
  diagnostics <- do.call(rbind, lapply(c("class", "reference"), function(scope) {
    data <- candidate[[scope]]$diagnostics
    if (is.null(data)) return(NULL)
    data.frame(Sample = if (scope == "class") "Latest group" else "Reference",
      Metric = data$metric, Value = data$value, stringsAsFactors = FALSE)
  }))
  # Never return row-level responses or duplicate identifiers to the UI process.
  list(results = candidate$results, diagnostics = diagnostics,
    selection = candidate$selection, demonstration = identical(candidate$results$metadata$data_mode, "demonstration"))
}

teacher_operation_worker <- function(operation, config, results = NULL, permission = NULL, cancellation = NULL) {
  check_active <- function() is.null(cancellation) || teacher_permission_valid(cancellation)
  assert_operation_active(check_active)
  if (operation == "refresh") {
    published <- get_current_published_results(config)
    return(list(type = "refreshed", results = published))
  }
  if (operation == "demo") return(list(type = "prepared", candidate = teacher_candidate_preview(prepare_demo_candidate(config))))
  if (operation == "update") {
    downloaded <- download_surveys_once(config, check_active = check_active)
    assert_operation_active(check_active)
    candidate <- prepare_latest_group_candidate(downloaded, config, check_active = check_active)
    assert_operation_active(check_active)
    return(list(type = "prepared", candidate = teacher_candidate_preview(candidate)))
  }
  if (operation == "publish") {
    if (identical(results$metadata$data_mode, "demonstration")) {
      stop("Demonstrations are private previews and cannot be published here.", call. = FALSE)
    }
    published <- publish_results_github(results, config, verify = TRUE,
      before_commit = function() check_active() && teacher_permission_valid(permission))
    return(list(type = "published", publication = published))
  }
  stop("Unknown teacher operation.", call. = FALSE)
}

# Finalise public terminal results in the promise callback itself, not a
# session observer. Disconnects cannot strand the lock after this returns.
teacher_finish_public_operation <- function(coordinator, id, value) {
  if (identical(value$type, "refreshed")) {
    message <- "The student site's published snapshot was loaded and checked."
    committed <- coordinator$state()$committed
    if (!is.null(committed) && !identical(committed$metadata$publication_id,
        value$results$metadata$publication_id)) {
      message <- "The student snapshot was loaded. The last known saved version has not been confirmed on the student site."
    }
    coordinator$finish(id, message, published = value$results)
    return(message)
  }
  if (!identical(value$type, "published")) return(NULL)
  publication <- value$publication
  confirmed <- isTRUE(publication$deployment$verified)
  unchanged <- identical(publication$changed, FALSE)
  message <- if (unchanged && confirmed) "No public data changed. The existing student publication was confirmed."
    else if (confirmed) "Published and confirmed on the student site."
    else "Saved in GitHub. Student deployment is pending or unconfirmed; the last confirmed group remains displayed."
  coordinator$finish(id, message,
    published = if (confirmed) publication$results else NULL, saved = publication$results)
  message
}
