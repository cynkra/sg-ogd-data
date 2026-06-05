# Example dataset script - safe to delete once you have real ones.
#
# Shows the contract every script in R/ follows: fetch -> (tidy) -> push to CKAN.
# This one builds a tiny synthetic table so it always runs green, demonstrating the
# framework without depending on a live website. For a real internet-scrape
# starting point, copy docs/TEMPLATE.R instead.
#
# The runner gives this script CKAN_URL, CKAN_API_KEY and SGOGD_ROOT in its
# environment. On success it exits 0; on any error it should stop() (non-zero
# exit), which the runner records as FAILURE and the daily Action turns into a
# GitHub issue.

source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))

# --- fetch (here: synthesize; normally an httr2 / readr call to a source URL) ---
df <- data.frame(
  date  = format(Sys.Date() - 6:0),
  value = round(seq(10, 20, length.out = 7), 1)
)

# --- push to CKAN ------------------------------------------------------------
# Guarded so the example stays green out of the box: it only uploads when a key is
# present AND SGOGD_EXAMPLE_UPLOAD=1 (the example's target dataset need not exist
# otherwise). Real scripts drop the guard and just call ckan_upload_csv().
upload <- nzchar(Sys.getenv("CKAN_API_KEY", "")) &&
          identical(Sys.getenv("SGOGD_EXAMPLE_UPLOAD", ""), "1")

if (upload) {
  ckan_upload_csv(dataset = "sg-ogd-data-example",
                  resource = "Example measurements",
                  data = df,
                  description = "Demo resource written by sg-ogd-data R/example.R.")
  cat(sprintf("uploaded %d rows to %s\n", nrow(df), ckan_base()))
} else {
  cat(sprintf("DRY RUN - fetched %d rows, upload skipped (no key / SGOGD_EXAMPLE_UPLOAD != 1)\n",
              nrow(df)))
}
