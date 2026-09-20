args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("Usage: Rscript scripts/check_concurrent_connections.R <url> <connections>")
}
url <- args[[1L]]
connections <- suppressWarnings(as.integer(args[[2L]]))
if (is.na(connections) || connections < 1L) stop("connections must be a positive integer.")
if (!requireNamespace("curl", quietly = TRUE)) stop("The curl package is required.")

pool <- curl::new_pool(total_con = connections, host_con = connections)
statuses <- integer()
errors <- character()
for (i in seq_len(connections)) {
  handle <- curl::new_handle(url = paste0(url, "?student=", i))
  curl::multi_add(
    handle,
    done = function(response) statuses <<- c(statuses, response$status_code),
    fail = function(error) errors <<- c(errors, conditionMessage(error)),
    pool = pool
  )
}
started <- Sys.time()
curl::multi_run(pool = pool, timeout = 30)
elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
if (length(errors) || length(statuses) != connections || any(statuses != 200L)) {
  stop(
    "Concurrent check failed: ", length(statuses), " responses, ",
    sum(statuses == 200L), " successful, ", length(errors), " errors."
  )
}
cat(sprintf("%d/%d static requests returned HTTP 200 in %.2f seconds.\n", connections, connections, elapsed))
