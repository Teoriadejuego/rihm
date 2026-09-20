source(file.path("R", "load_all.R"))
source_project_modules(".")

config <- read_app_config(".")
candidate <- prepare_demo_candidate(config, demo_session_code())
preview_root <- file.path(config$project_root, "staging", "demo-preview")
student_root <- file.path(preview_root, "student")
dir.create(student_root, recursive = TRUE, showWarnings = FALSE)
source_files <- file.path(config$project_root, "student", c("index.qmd", "app.js", "styles.css"))
if (!all(file.copy(source_files, student_root, overwrite = TRUE))) {
  stop("Could not copy the demonstration site source.")
}
if (!file.copy(file.path(config$project_root, "student", "assets"), student_root,
               recursive = TRUE, overwrite = TRUE)) {
  stop("Could not copy the demonstration assets.")
}
write_public_snapshot(candidate$results, preview_root, secrets = demo_session_code(), save_snapshot = FALSE)
invisible(render_student_site(preview_root))
scan_public_files(preview_root, secrets = demo_session_code())
cat("Synthetic preview ready at", file.path(student_root, "_site"), "\n")
cat("No public snapshot was changed and nothing was pushed.\n")
