args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args)) args[[1L]] else file.path(tempdir(), "public_results.json")
source(file.path("R", "load_all.R"))
source_project_modules(".")

grid <- expand.grid(rep(list(0:1), 6), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
names(grid) <- decision_columns

class <- grid[rep(seq_len(nrow(grid)), each = 10L), , drop = FALSE]
class <- classify_preferences(class)
class$gender_code <- rep(c(1, 2), length.out = nrow(class))
class$country <- "Spain"

countries <- c("Dominican Republic", "Ivory Coast", "Madagascar", "Philippines", "Salvador", "Spain")
reference <- do.call(rbind, lapply(countries, function(country) {
  data <- grid[rep(seq_len(nrow(grid)), each = 10L), , drop = FALSE]
  data <- classify_preferences(data)
  data$gender_code <- rep(c(1, 2), length.out = nrow(data))
  data$country <- country
  data
}))

results <- build_public_results(
  class,
  reference,
  minimum_cell_size = 5L,
  source_snapshot_at_utc = Sys.time(),
  publication_id = "visual-test-only"
)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(results, output, dataframe = "rows", na = "null", auto_unbox = TRUE, pretty = TRUE)
cat("Synthetic visual-test snapshot written to", normalizePath(output, winslash = "/"), "\n")

