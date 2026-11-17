testthat::test_that("the public artifact scan requires coherent matching files", {
  root <- tempfile("public-scan-")
  directory <- file.path(root, "student", "data")
  dir.create(directory, recursive = TRUE)
  original <- testthat::test_path("..", "..", "student", "data")
  file.copy(file.path(original, c("public_results.json", "public_manifest.json")), directory)
  testthat::expect_silent(scan_public_files(root))
  manifest_file <- file.path(directory, "public_manifest.json")
  manifest <- jsonlite::read_json(manifest_file, simplifyVector = TRUE)
  manifest$publication_id <- "tampered-publication"
  jsonlite::write_json(manifest, manifest_file, auto_unbox = TRUE)
  testthat::expect_error(scan_public_files(root), "manifest does not match")
  unlink(manifest_file)
  testthat::expect_error(scan_public_files(root), "missing its matching")
})

testthat::test_that("built public content rejects supplied private values", {
  root <- tempfile("private-scan-")
  directory <- file.path(root, "student", "_site")
  dir.create(directory, recursive = TRUE)
  writeLines("test-secret-never-public", file.path(directory, "index.html"))
  testthat::expect_error(scan_public_files(root, secrets = "test-secret-never-public"), "Privacy scan failed")
})
