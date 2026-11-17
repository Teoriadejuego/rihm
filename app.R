# Hosted entrypoint: cloud mode always requires authentication and uses GitHub
# APIs. The local teacher launcher continues to run admin/app.R directly.
if (.Platform$OS.type == "windows" && !isTRUE(l10n_info()[["UTF-8"]])) {
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
}
if (file.exists("hosting.env")) readRenviron("hosting.env")
Sys.setenv(TEACHER_HOST_MODE = "cloud")
source(file.path("admin", "app.R"), local = TRUE, encoding = "UTF-8")$value
