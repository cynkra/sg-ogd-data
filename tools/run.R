#!/usr/bin/env Rscript
# Discover every dataset script in R/ and run each one in its own isolated Rscript
# process, recording SUCCESS / FAILURE (+ the captured error) for each.
#
# Adding a dataset is the only thing a contributor does: drop one self-contained
# `R/<dataset>.R` that fetches its data and pushes it to CKAN. This runner finds it
# automatically - there is no central file to register it in.
#
# Per-script isolation (a separate Rscript per file) is deliberate: one broken or
# slow script can never abort the others or the whole run. Exit code 0 = SUCCESS;
# any R error, explicit stop(), or quit(status = 1) = FAILURE, with the tail of the
# script's stderr kept as the error message.
#
# Each child inherits CKAN_URL, CKAN_API_KEY and SGOGD_ROOT from this process.
#
# Writes status/run.json (this run's outcome). ALWAYS exits 0 itself, so the render
# and commit steps still run when some scripts fail - the failures surface as the
# health board going red and as GitHub issues, not as a dead workflow.
#
# Run: Rscript tools/run.R

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

root <- tryCatch(
  dirname(dirname(normalizePath(sub("--file=", "",
    grep("--file=", commandArgs(FALSE), value = TRUE))))),
  error = function(e) normalizePath("."))
setwd(root)

ckan_url <- Sys.getenv("CKAN_URL", "https://ogd.cynkra.dev")
Sys.setenv(SGOGD_ROOT = root, CKAN_URL = ckan_url)

scripts <- sort(list.files("R", pattern = "\\.[Rr]$", full.names = TRUE))
cat(sprintf("sg-ogd-data: %d dataset script(s) in R/  ->  %s\n\n",
            length(scripts), ckan_url))

run_one <- function(path) {
  id <- sub("\\.[Rr]$", "", basename(path))
  t0 <- Sys.time()
  out <- suppressWarnings(system2("Rscript", c("--vanilla", shQuote(path)),
                                  stdout = TRUE, stderr = TRUE))
  code <- as.integer(attr(out, "status") %||% 0L)
  dur  <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  ok   <- identical(code, 0L)
  err  <- if (ok) "" else paste(tail(out, 8L), collapse = "\n")
  cat(sprintf("  %-4s %-30s %5.1fs%s\n", if (ok) "OK" else "FAIL", id, dur,
              if (ok) "" else sprintf("  | %s", sub("\n.*", "", err))))
  list(script = basename(path), id = id,
       status = if (ok) "SUCCESS" else "FAILURE",
       duration_s = dur, error = err)
}

records  <- lapply(scripts, run_one)
fail_ids <- vapply(Filter(function(r) r$status == "FAILURE", records),
                   function(r) r$id, "")
n_ok     <- length(records) - length(fail_ids)

dir.create("status", showWarnings = FALSE)
run <- list(
  ts      = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
  n       = length(records),
  ok      = n_ok,
  failed  = length(fail_ids),
  scripts = records
)
writeLines(toJSON(run, auto_unbox = TRUE, pretty = TRUE, null = "null"),
           file.path("status", "run.json"))

cat(sprintf("\n%d ok, %d failed -> status/run.json\n", n_ok, length(fail_ids)))
