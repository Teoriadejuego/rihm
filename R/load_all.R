source_project_modules <- function(project_root = ".") {
  # Some Windows launchers inherit the Linux-only C.UTF-8 locale. Restore an
  # available UTF-8 character locale before reading labels and source files.
  if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]])) {
    suppressWarnings(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
  }
  files <- c(
    "config.R", "fetch_qualtrics.R", "normalize.R", "classify.R", "validate.R",
    "aggregate.R", "public_results.R", "pipeline.R", "publication.R", "demo.R",
    "teacher_auth.R", "github_publication.R", "teacher_coordinator.R"
  )
  for (file in files) {
    source(file.path(project_root, "R", file), local = .GlobalEnv, encoding = "UTF-8")
  }
  invisible(files)
}
