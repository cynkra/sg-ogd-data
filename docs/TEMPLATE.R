# TEMPLATE - copy this to R/<your-dataset>.R and adapt it.
#
# Name the file after its CKAN dataset (e.g. R/wetterdaten-stadt-sg.R). The runner
# (tools/run.R) discovers every R/*.R automatically - there is nothing else to
# register. Your script's job:
#
#   1. fetch data from the internet,
#   2. (optionally) tidy it,
#   3. push it to CKAN with ckan_upload_csv().
#
# Status contract:
#   - finish normally               -> SUCCESS (green on the board)
#   - stop() / error / quit(st = 1) -> FAILURE (red, opens a GitHub issue)
# So let real problems error out - do NOT wrap the whole thing in tryCatch() and
# swallow it, or a broken source will look healthy.
#
# Environment (set for you by the runner / the GitHub Action):
#   CKAN_URL      target instance        (default https://ogd.cynkra.dev)
#   CKAN_API_KEY  your CKAN API token    (the repo's GitHub Actions secret)
#   SGOGD_ROOT    repo root, for source()ing the helper below

source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))

# ---------------------------------------------------------------------------
# Example: pull pattern (Simon's reference dataset #2) - a clean CSV published
# at a stable URL by MeteoSchweiz and refreshed several times a day.
# NOTE: verify the exact asset URL for your station before relying on it.
# ---------------------------------------------------------------------------

SRC     <- "https://data.geo.admin.ch/ch.meteoschweiz.messwerte-aktuell/ogd-smn_stg_t_recent.csv"
DATASET <- "wetterdaten-stadt-sg"   # the CKAN dataset must already exist

# Fetch. readr / httr2 will raise an error on a bad response, which is exactly the
# FAILURE signal we want.
df <- readr::read_delim(SRC, delim = ";", show_col_types = FALSE)

# Tidy here if needed (rename columns, parse dates, drop junk rows, ...).

# Push. Find-or-update by resource name keeps one stable, refreshed resource.
ckan_upload_csv(
  dataset     = DATASET,
  resource    = "Aktuelle Messwerte",
  data        = df,
  description = "Automatisch aktualisiert aus data.geo.admin.ch (MeteoSchweiz)."
)

cat(sprintf("uploaded %d rows to %s/%s\n", nrow(df), ckan_base(), DATASET))
