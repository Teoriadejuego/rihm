options(warn = 1)
source(file.path("R", "load_all.R"))
source_project_modules(".")
testthat::test_dir(file.path("tests", "testthat"), reporter = "summary", stop_on_failure = TRUE)

