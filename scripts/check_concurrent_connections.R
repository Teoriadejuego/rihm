args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: Rscript scripts/check_concurrent_connections.R <url> <clients>")
base <- paste0(sub("/+$", "", args[[1L]]), "/")
connections <- suppressWarnings(as.integer(args[[2L]]))
if (is.na(connections) || connections < 1L) stop("connections must be a positive integer.")
if (!requireNamespace("curl", quietly = TRUE)) stop("The curl package is required.")
if (!grepl("^https?://", base)) stop("Provide an HTTP or HTTPS site URL.")
html <- rawToChar(curl::curl_fetch_memory(base)$content)
links <- regmatches(html, gregexpr("(?:src|href)=[\"'][^\"']+[\"']", html, perl = TRUE))[[1L]]
links <- sub("^[^=]+=[\"']", "", sub("[\"']$", "", links))
assets <- links[grepl("[.](js|css)([?].*)?$", links) & !grepl("^(https?:)?//", links)]
origin <- sub("^(https?://[^/]+).*$", "\\1", base)
asset_urls <- vapply(assets, function(path) {
  if (startsWith(path, "/")) paste0(origin, path) else paste0(base, sub("^[.]/", "", path))
}, character(1))
resources <- unique(c(base, asset_urls, paste0(base, "data/public_manifest.json"), paste0(base, "data/public_results.json")))
if (!length(asset_urls)) stop("No JavaScript or stylesheet assets discovered in the document.")

pool <- curl::new_pool(total_con = connections, host_con = connections)
statuses <- integer()
errors <- 0L
bytes <- 0
for (i in seq_len(connections)) {
  for (url in resources) {
  handle <- curl::new_handle(url = url, timeout = 60)
  curl::multi_add(
    handle,
    done = function(response) {
      statuses <<- c(statuses, response$status_code)
      bytes <<- bytes + length(response$content)
    },
    fail = function(error) { errors <<- errors + 1L },
    pool = pool
  )
  }
}
started <- Sys.time()
invisible(curl::multi_run(pool = pool, timeout = 90))
elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
expected <- connections * length(resources)
if (errors || length(statuses) != expected || any(statuses != 200L)) {
  stop(
    "Concurrent check failed: ", length(statuses), " responses, ",
    sum(statuses == 200L), " successful, ", errors, " errors."
  )
}
cat(sprintf("%d simulated clients, %d resources each: %d/%d HTTP 200 in %.2fs; %.2f MB delivered.\n",
  connections, length(resources), length(statuses), expected, elapsed, bytes / 1e6))
cat("This checks concurrent static delivery, not browser rendering or a guaranteed capacity limit.\n")
