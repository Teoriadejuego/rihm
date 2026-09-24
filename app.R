# Hosted entrypoint: cloud mode always requires authentication and uses GitHub
# APIs. The local teacher launcher continues to run admin/app.R directly.
if (file.exists("hosting.env")) readRenviron("hosting.env")
Sys.setenv(TEACHER_HOST_MODE = "cloud")
source(file.path("admin", "app.R"), local = TRUE)$value
