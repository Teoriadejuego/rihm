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

testthat::test_that("a valid but different built snapshot cannot pass the artifact scan", {
  root <- tempfile("stale-artifact-")
  input <- file.path(root, "student", "data")
  built <- file.path(root, "student", "_site", "data")
  dir.create(input, recursive = TRUE)
  dir.create(built, recursive = TRUE)
  original <- testthat::test_path("..", "..", "student", "data")
  files <- c("public_results.json", "public_manifest.json")
  file.copy(file.path(original, files), input)
  file.copy(file.path(original, files), built)
  testthat::expect_silent(scan_public_files(root))
  path <- file.path(built, "public_results.json")
  text <- paste0(rawToChar(readBin(path, "raw", file.info(path)$size)), " ")
  results <- jsonlite::fromJSON(text, simplifyVector = TRUE)
  writeBin(charToRaw(text), path)
  jsonlite::write_json(public_manifest(results, text), file.path(built, "public_manifest.json"), auto_unbox = TRUE)
  testthat::expect_error(scan_public_files(root), "built artifact differs")
})

public_scan_fixture <- function() {
  root <- tempfile("closed-public-scan-")
  original <- testthat::test_path("..", "..", "student", "data")
  for (directory in file.path(root, "student", c("data", "_site/data"))) {
    dir.create(directory, recursive = TRUE)
    invisible(file.copy(file.path(original, c("public_results.json", "public_manifest.json")), directory))
  }
  root
}

testthat::test_that("the public scan allows reviewed HTML, generated assets and the exact JSON pair", {
  root <- public_scan_fixture()
  built <- file.path(root, "student", "_site")
  dir.create(file.path(built, "assets"))
  writeLines("<main>Protected aggregates</main>", file.path(built, "index.html"))
  writeLines("document.title = 'Classroom';", file.path(built, "assets", "index-Abc_1234.js"))
  writeLines("body { color: black; }", file.path(built, "assets", "index-Abc-1234.css"))
  testthat::expect_length(scan_public_files(root), 7L)
})

testthat::test_that("public inputs cannot contain any extra files or hidden directories", {
  for (name in c("extra.json", "raw.csv", ".env", "nested/extra.json", ".cache/extra.json")) {
    root <- public_scan_fixture()
    path <- file.path(root, "student", "data", name)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("synthetic-private-marker", path)
    testthat::expect_error(scan_public_files(root), "unexpected public file or directory")
  }
})

testthat::test_that("built artifacts reject unknown types and hidden outputs instead of skipping them", {
  for (name in c("debug.log", "unknown.bin", ".env", "assets/.hidden.js",
    "assets/source.js.map", "assets/notes.txt", "assets/unversioned.js", "data/extra.json", ".private/index.html")) {
    root <- public_scan_fixture()
    path <- file.path(root, "student", "_site", name)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("synthetic-private-marker", path)
    testthat::expect_error(scan_public_files(root, secrets = "synthetic-private-marker"),
      "unexpected public file or directory")
  }
  root <- public_scan_fixture()
  dir.create(file.path(root, "student", "_site", ".empty-hidden"))
  testthat::expect_error(scan_public_files(root), "unexpected public file or directory")
})
