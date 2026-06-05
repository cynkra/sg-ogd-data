# sg-ogd-data

[![ETL](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/cynkra/sg-ogd-data/main/status/badge.json)](STATUS.md)

Automated open-data scrapers for the **Kanton St.Gallen OGD platform**. Each
script in [`R/`](R/) fetches one dataset from the internet and pushes it to the SG
CKAN instance ([ogd.cynkra.dev](https://ogd.cynkra.dev)) via the CKAN API. A daily
GitHub Action runs them all and tracks which ones succeeded.

It is **not** an R package - `R/` is a folder of standalone scrape scripts. The
repo stores the *health history*, not the data; the data lives in CKAN.

## Add a dataset (the only thing you do)

Drop one self-contained script into `R/`, named after its dataset:

```r
# R/my-dataset.R
source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))

df <- readr::read_delim("https://.../data.csv", delim = ";", show_col_types = FALSE)

ckan_upload_csv(dataset = "my-dataset", resource = "Aktuelle Daten", data = df)
```

That's it - the runner discovers it automatically, no central file to edit. Copy
[`docs/TEMPLATE.R`](docs/TEMPLATE.R) to start. Full guide: [CONTRIBUTING.md](CONTRIBUTING.md).

**Status contract:** finish normally = `SUCCESS`; `stop()`/error = `FAILURE`. Let
real problems error out - don't swallow them in a `tryCatch()`.

## Health

<!-- HEALTH:START -->
**ETL status** (run 2026-06-05): 🟢 1 of 1 script(s) green.

![ETL uptime](status/health.svg)

See [STATUS.md](STATUS.md) for the per-script board.
<!-- HEALTH:END -->

Each script gets one row in the graph (green = succeeded that day, red = failed,
grey = did not run). A failing script automatically opens a GitHub issue and
auto-closes it when it recovers.

## Layout

| Path | What |
|---|---|
| `R/` | dataset scrape scripts - **one file per dataset**, auto-discovered |
| `tools/run.R` | runs every `R/*.R` in an isolated process, writes `status/run.json` |
| `tools/render.R` | rolls runs into the history + renders the graph, `STATUS.md`, README block |
| `tools/ckan.R` | CKAN API helpers (`ckan_upload_csv()`, `ckan_action()`) that scripts source |
| `docs/TEMPLATE.R` | copy-me starting point for a new dataset |
| `status/` | committed health history (`history.csv`, `script-history.csv`, `health.svg`, `badge.json`) |
| `STATUS.md` | per-script board, latest run |
| `.github/workflows/etl.yml` | the daily Action |

## CKAN credentials

Scripts authenticate with a CKAN API token taken from the environment:

- `CKAN_API_KEY` - a **scoped, non-sysadmin** CKAN API token (the `github-ingest`
  user, editor on the SG organisations only), stored as a **GitHub Actions
  secret**. It grants dataset writes, not instance administration, so a leak
  cannot compromise CKAN. The secret never appears in this repo or its logs.
- `CKAN_URL` - the instance, defaults to `https://ogd.cynkra.dev`.

Maintainers mint and rotate this token on the CKAN host; the procedure lives in
cynkra's internal ops notes, not in this public repo.

## Run it locally

```bash
export CKAN_API_KEY=...        # optional; without it, uploads are skipped (dry run)
Rscript tools/run.R            # run all R/*.R, write status/run.json
Rscript tools/render.R         # render the health board
```
