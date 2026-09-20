testthat::test_that("publication commands preserve commit messages and paths with spaces", {
  testthat::skip_if(!nzchar(Sys.which("git")), "Git is required")
  repository <- tempfile("publication repository ")
  dir.create(repository)

  run_checked_command("git", c("init", "--quiet"), repository)
  filename <- "public results.json"
  writeLines("{}", file.path(repository, filename))
  run_checked_command("git", c("add", "--", filename), repository)
  message <- "Publish classroom results regression-2026"
  run_checked_command(
    "git",
    c("-c", "user.name=Publication Regression", "-c",
      "user.email=regression@example.invalid", "-c", "commit.gpgsign=false",
      "commit", "--quiet", "-m", message, "--", filename),
    repository
  )

  testthat::expect_identical(
    run_checked_command("git", c("log", "-1", "--format=%s"), repository),
    message
  )
  testthat::expect_identical(
    run_checked_command("git", c("ls-tree", "--name-only", "HEAD"), repository),
    filename
  )
})
