packages <- c("bslib", "httr2", "jsonlite", "qualtRics", "shiny", "shinymanager", "sodium", "testthat", "uuid", "yaml")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
cat("R dependencies are available.\n")
