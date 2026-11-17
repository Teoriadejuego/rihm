if (!requireNamespace("renv", quietly = TRUE)) {
  stop("Install renv before recording dependency versions.", call. = FALSE)
}
options(repos = c(CRAN = "https://cloud.r-project.org"))
renv::snapshot(project = ".", type = "explicit", prompt = FALSE)
