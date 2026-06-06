# Example dataset script - the simplest real one: a heartbeat.
#
# Every run it posts a one-row CSV holding the timestamp of this update to CKAN,
# so you can see the daily ETL is alive and actually writing. Copy docs/TEMPLATE.R
# for a real internet-scrape; this one needs no external source.
#
# Contract: the runner gives this script CKAN_URL, CKAN_API_KEY and SGOGD_ROOT.
# Finishing normally = SUCCESS; any error (e.g. a missing token) = FAILURE, which
# the daily Action turns into a GitHub issue. In dry-run mode (SGOGD_DRYRUN=1, used
# by the PR check) the CKAN calls are no-ops, so it stays green without a secret.

source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))

ORG     <- "kanton-st-gallen"          # SG playground org (token is editor here)
DATASET <- "sg-ogd-data-example"

df <- data.frame(
  updated_utc      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  updated_local_ch = format(Sys.time(), "%Y-%m-%d %H:%M:%S",  tz = "Europe/Zurich"),
  source           = "https://github.com/cynkra/sg-ogd-data",
  note             = "Automatischer Heartbeat des sg-ogd-data ETL"
)

ckan_ensure_dataset(
  DATASET,
  title     = "sg-ogd-data – Beispiel (letzte Aktualisierung)",
  owner_org = ORG,
  notes     = paste("Automatischer Beispiel-Datensatz des sg-ogd-data ETL.",
                    "Enthaelt den Zeitpunkt der letzten Aktualisierung.")
)

invisible(ckan_upload_csv(
  dataset     = DATASET,
  resource    = "Letzte Aktualisierung",
  data        = df,
  description = "Zeitstempel des letzten automatischen ETL-Laufs (UTC und Lokalzeit)."
))

cat(sprintf("posted heartbeat %s to %s/dataset/%s\n",
            df$updated_utc, ckan_base(), DATASET))
