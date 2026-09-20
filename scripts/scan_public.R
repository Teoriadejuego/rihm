source(file.path("R", "load_all.R"))
source_project_modules(".")
scan_public_files(".")
cat("Public privacy scan passed.\n")

