testthat::test_that("hosted bundles use a closed whitelist and preserve the caller environment", {
  bundle_module <- new.env(parent = globalenv())
  sys.source(file.path("..", "..", "scripts", "prepare_hosted_bundle.R"), envir = bundle_module)
  root <- tempfile("bundle-fixture-")
  for (directory in c("admin", "R", "config", "snapshots", "staging", "student")) {
    dir.create(file.path(root, directory), recursive = TRUE)
  }
  for (path in c("app.R", "admin/app.R", "R/load_all.R", "R/helper.R", "config/reference_locations.csv",
    "config/config.yml", ".Renviron", "snapshots/private.json", "student/private.json", "R/notes.txt")) {
    writeLines("fixture", file.path(root, path))
  }
  writeLines(c("Package: fixture", "Imports: shiny, httr2"), file.path(root, "DESCRIPTION"))
  hosting <- file.path(root, "config", "hosting.Renviron")
  writeLines(c("TEACHER_USERNAME=fixture", 'TEACHER_PASSWORD="fixture-password-123456789"',
    "GITHUB_PUBLICATION_TOKEN=test-token"), hosting)
  old_password <- Sys.getenv("TEACHER_PASSWORD", unset = NA_character_)
  on.exit(if (is.na(old_password)) Sys.unsetenv("TEACHER_PASSWORD") else Sys.setenv(TEACHER_PASSWORD = old_password), add = TRUE)
  Sys.setenv(TEACHER_PASSWORD = "ambient-value")
  stamp <- as.POSIXct("2026-09-24 12:00:00", tz = "UTC")
  bundle <- bundle_module$prepare_hosted_bundle(root, stamp)
  testthat::expect_identical(Sys.getenv("TEACHER_PASSWORD"), "ambient-value")
  testthat::expect_identical(basename(bundle), "teacher-hosted-20260924T120000Z")
  testthat::expect_setequal(list.files(bundle, recursive = TRUE, all.files = TRUE, no.. = TRUE),
    c("app.R", "admin/app.R", "R/load_all.R", "R/helper.R", "DESCRIPTION", "config/reference_locations.csv", "hosting.env"))
  testthat::expect_identical(readBin(file.path(bundle, "hosting.env"), "raw", 10000), readBin(hosting, "raw", 10000))
  second <- bundle_module$prepare_hosted_bundle(root, stamp)
  testthat::expect_identical(basename(second), "teacher-hosted-20260924T120000Z-2")
  testthat::expect_true(file.exists(file.path(bundle, "hosting.env")))
})

testthat::test_that("bundling fails closed for missing or weak private passwords without exposing values", {
  bundle_module <- new.env(parent = globalenv())
  sys.source(file.path("..", "..", "scripts", "prepare_hosted_bundle.R"), envir = bundle_module)
  root <- tempfile("bundle-invalid-")
  dir.create(file.path(root, "config"), recursive = TRUE)
  private <- file.path(root, "config", "hosting.Renviron")
  testthat::expect_error(bundle_module$prepare_hosted_bundle(root), "ignored config/hosting.Renviron")
  for (contents in c("TEACHER_USERNAME=fixture", "TEACHER_PASSWORD=SECRET-SHORT",
    "TEACHER_PASSWORD=${AMBIENT_PRIVATE_PASSWORD}", "UNEXPECTED_SETTING=SECRET-SHORT",
    "TEACHER_PASSWORD=123456789012345678901\nTEACHER_PASSWORD=SECRET-SHORT")) {
    writeLines(contents, private)
    error <- tryCatch(bundle_module$prepare_hosted_bundle(root), error = identity)
    testthat::expect_s3_class(error, "error")
    testthat::expect_false(grepl("SECRET-SHORT|AMBIENT_PRIVATE_PASSWORD", conditionMessage(error)))
    testthat::expect_false(dir.exists(file.path(root, "staging")))
  }
})
