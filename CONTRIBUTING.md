# Adding a dataset

You add a dataset by adding **one R script** to [`R/`](R/). Nothing else - no
central list to register it in, no build config. The daily GitHub Action discovers
every `R/*.R`, runs it, pushes its data to CKAN, and tracks whether it succeeded.

## 1. Copy the template

```bash
cp docs/TEMPLATE.R R/my-dataset.R
```

Name the file after its CKAN dataset (the package "name" slug), e.g.
`R/wetterdaten-stadt-sg.R`.

## 2. Write three steps

```r
source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))

# 1. fetch
df <- readr::read_delim("https://example.ch/data.csv", delim = ";",
                        show_col_types = FALSE)

# 2. tidy (optional) - rename columns, parse dates, drop junk rows ...

# 3. push to CKAN
ckan_upload_csv(
  dataset  = "my-dataset",          # must already exist in CKAN
  resource = "Aktuelle Daten",      # find-or-update by this name
  data     = df                     # a data.frame, or a path to a .csv
)
```

`ckan_upload_csv()` creates the resource the first time and patches the file on
every later run, so the dataset keeps one stable, refreshed resource. Uploading a
CSV triggers XLoader, which loads it into the DataStore API automatically. For
anything the helper doesn't cover, use the low-level `ckan_action(<action>, ...)`.

## 3. The status contract

| Your script... | Recorded as | On the board |
|---|---|---|
| finishes normally (exit 0) | `SUCCESS` | 🟢 green |
| calls `stop()`, errors, or `quit(status = 1)` | `FAILURE` | 🔴 red + a GitHub issue |

**Let real problems error out.** Do not wrap the whole script in `tryCatch()` and
swallow the error - a source that silently fails will look healthy while the data
goes stale. A bad HTTP response from `httr2`/`readr` already errors, which is the
behaviour you want.

Each script runs in its own process, so yours can't break anyone else's.

## 4. Test locally

```bash
export CKAN_API_KEY=...     # a CKAN token; omit to dry-run the fetch without uploading
Rscript tools/run.R         # runs all R/*.R, prints OK/FAIL per script
Rscript tools/render.R      # updates STATUS.md + the README graph
```

Run just your script in isolation while developing:

```bash
SGOGD_ROOT=. CKAN_API_KEY=... Rscript --vanilla R/my-dataset.R
```

## 5. Extra packages

The Action installs a base toolkit (`httr2`, `curl`, `jsonlite`, `readr`,
`readxl`, `dplyr`, `tidyr`, `stringr`, `tibble`). If your script needs another
package, add it to the install list in
[`.github/workflows/etl.yml`](.github/workflows/etl.yml).
