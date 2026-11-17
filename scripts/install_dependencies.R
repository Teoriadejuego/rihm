packages <- c("bslib", "curl", "future", "httr2", "jsonlite", "openssl", "promises", "qualtRics", "shiny", "shinymanager", "sodium", "testthat", "uuid", "yaml")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
cat("R dependencies are available.\n")
