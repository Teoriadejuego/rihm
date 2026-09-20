source_project_modules <- function(project_root = ".") {
  files <- c(
    "config.R", "fetch_qualtrics.R", "normalize.R", "classify.R", "validate.R",
    "aggregate.R", "public_results.R", "pipeline.R", "publication.R"
  )
  for (file in files) {
    source(file.path(project_root, "R", file), local = .GlobalEnv)
  }
  invisible(files)
}

