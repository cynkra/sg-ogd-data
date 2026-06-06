#!/usr/bin/env Rscript
# Roll status/run.json up into the committed health history and render the README
# graph + the per-script board. Mirrors the UPTIME.md machinery in
# cynkra/dataseries-data, simplified to a single per-script metric: did this
# script's scrape succeed today (green) or fail (red).
#
# Reads  : status/run.json                (this run, from tools/run.R)
# Writes : status/script-history.csv       one row per script per day - the history
#          status/history.csv              one row per day - the overall roll-up
#          status/health.svg               status grid, last 90 days, no plot deps
#          status/badge.json               shields.io endpoint badge
#          STATUS.md                       per-script board (latest run)
#          README.md                       the <!-- HEALTH --> block (summary + graph)
#
# Run: Rscript tools/render.R   (after tools/run.R; the daily Action runs both)

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

root <- tryCatch(
  dirname(dirname(normalizePath(sub("--file=", "",
    grep("--file=", commandArgs(FALSE), value = TRUE))))),
  error = function(e) normalizePath("."))
setwd(root)
ST <- "status"
dir.create(ST, showWarnings = FALSE)

run    <- fromJSON(file.path(ST, "run.json"), simplifyVector = FALSE)
today  <- format(Sys.Date())
ts     <- run$ts %||% format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ")

scripts <- run$scripts %||% list()
ids     <- vapply(scripts, function(s) s$id %||% s$script %||% "?", "")
stat    <- vapply(scripts, function(s) s$status %||% "FAILURE", "")
errs    <- setNames(vapply(scripts, function(s) s$error %||% "", ""), ids)
durs    <- setNames(vapply(scripts, function(s) as.numeric(s$duration_s %||% NA), 0), ids)
fail_ids <- ids[stat == "FAILURE"]

GREEN <- "green"; RED <- "red"
script_status <- setNames(ifelse(stat == "SUCCESS", GREEN, RED), ids)

# --- status/script-history.csv : upsert today's per-script rows -------------
SH   <- file.path(ST, "script-history.csv")
SCOL <- c("date", "script", "status")
today_rows <- data.frame(date = today, script = ids,
                         status = unname(script_status[ids]),
                         stringsAsFactors = FALSE)
hist <- if (file.exists(SH)) read.csv(SH, colClasses = "character") else today_rows[0, ]
hist <- hist[!(hist$date == today & hist$script %in% ids), , drop = FALSE]  # idempotent re-run
hist <- rbind(hist, today_rows)
hist <- hist[order(hist$date, hist$script), , drop = FALSE]
write.csv(hist[, SCOL], SH, row.names = FALSE, quote = TRUE)

# --- status/history.csv : upsert today's overall row ------------------------
H    <- file.path(ST, "history.csv")
HCOL <- c("date", "n_scripts", "n_ok", "n_failed", "failed", "status")
overall <- data.frame(
  date = today, n_scripts = length(ids), n_ok = sum(stat == "SUCCESS"),
  n_failed = length(fail_ids), failed = paste(fail_ids, collapse = ";"),
  status = if (length(fail_ids)) RED else GREEN, stringsAsFactors = FALSE)
oh <- if (file.exists(H)) read.csv(H, colClasses = "character") else overall[0, ]
oh <- oh[oh$date != today, , drop = FALSE]
oh <- rbind(oh, overall)
oh <- oh[order(oh$date), , drop = FALSE]
write.csv(oh[, HCOL], H, row.names = FALSE, quote = TRUE)

# --- per-script uptime % over a trailing window -----------------------------
script_uptime <- function(s, days = 30) {
  h <- hist[hist$script == s, ]
  h <- h[as.Date(h$date) > (Sys.Date() - days), ]
  if (!nrow(h)) return(NA_real_)
  round(100 * mean(h$status == GREEN))
}

# --- status/health.svg : status grid, one row per current script ------------
# Last 90 calendar days. A day with no record renders grey (the script did not run
# that day - e.g. it did not exist yet, or the whole workflow failed), which is
# what we want the long-term picture to show.
write_svg <- function(path) {
  col <- c(green = "#2ea44f", red = "#cf222e", grey = "#d0d7de")
  ndays <- 90L
  days  <- seq(Sys.Date() - (ndays - 1L), Sys.Date(), by = "day")
  rows  <- lapply(sort(ids), function(s) {
    colors <- vapply(days, function(d) {
      r <- hist[hist$date == format(d) & hist$script == s, "status"]
      if (!length(r)) col[["grey"]] else col[[r[1]]]
    }, "")
    list(label = s, colors = colors)
  })
  if (!length(rows)) rows <- list(list(label = "(no scripts yet)",
                                       colors = rep(col[["grey"]], ndays)))

  pad_l <- 230L; pad_t <- 70L
  cw <- 8L; ch <- 18L; gap <- 2L; rgap <- 8L
  width  <- pad_l + ndays * (cw + gap) + 20L
  height <- pad_t + length(rows) * (ch + rgap) + 56L
  esc <- function(x) gsub("&", "&amp;", x, fixed = TRUE)

  p <- c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="-apple-system,Segoe UI,Helvetica,Arial,sans-serif">', width, height),
         sprintf('<rect width="%d" height="%d" fill="#ffffff"/>', width, height),
         sprintf('<text x="20" y="30" font-size="18" font-weight="600" fill="#1f2328">ETL uptime &#8212; last %d days</text>', ndays),
         sprintf('<text x="20" y="50" font-size="12" fill="#656d76">%d script(s) &#183; %d green / %d red this run &#183; generated %s</text>',
                 length(ids), sum(stat == "SUCCESS"), length(fail_ids), today))
  for (ri in seq_along(rows)) {
    y <- pad_t + (ri - 1L) * (ch + rgap)
    p <- c(p, sprintf('<text x="%d" y="%d" font-size="12" fill="#1f2328" text-anchor="end">%s</text>',
                      pad_l - 12L, y + ch - 5L, esc(rows[[ri]]$label)))
    for (di in seq_len(ndays)) {
      x <- pad_l + (di - 1L) * (cw + gap)
      p <- c(p, sprintf('<rect x="%d" y="%d" width="%d" height="%d" rx="1.5" fill="%s"/>',
                        x, y, cw, ch, rows[[ri]]$colors[di]))
    }
  }
  axis_y <- pad_t + length(rows) * (ch + rgap) + 14L
  p <- c(p, sprintf('<text x="%d" y="%d" font-size="11" fill="#656d76">%s</text>', pad_l, axis_y, format(days[1])),
            sprintf('<text x="%d" y="%d" font-size="11" fill="#656d76" text-anchor="end">%s</text>', width - 20L, axis_y, format(days[ndays])))
  ly <- axis_y + 22L; lx <- pad_l
  for (lg in list(c(col[["green"]], "success"), c(col[["red"]], "failure"), c(col[["grey"]], "no run"))) {
    p <- c(p, sprintf('<rect x="%d" y="%d" width="12" height="12" rx="1.5" fill="%s"/>', lx, ly - 10L, lg[1]),
              sprintf('<text x="%d" y="%d" font-size="11" fill="#656d76">%s</text>', lx + 16L, ly, lg[2]))
    lx <- lx + 90L
  }
  writeLines(c(p, "</svg>"), path)
}
write_svg(file.path(ST, "health.svg"))

# --- STATUS.md : per-script board (latest run) ------------------------------
emoji <- function(s) if (s == GREEN) "\U0001F7E2" else "\U0001F534"
ord   <- order(stat != "FAILURE", ids)   # failures first, then alphabetical
md <- c(
  "# ETL status",
  "",
  sprintf("_Last run: **%s**. Auto-generated by `tools/render.R`. Do not edit by hand._", ts),
  "",
  sprintf("\U0001F7E2 %d ok \U00B7 \U0001F534 %d failed \U2014 %d script(s)",
          sum(stat == "SUCCESS"), length(fail_ids), length(ids)),
  "",
  "| | Dataset script | Last run | Uptime 30d | Note |",
  "|---|---|---|---:|---|")
for (i in ord) {
  id <- ids[i]
  note <- if (stat[i] == "FAILURE") gsub("\n", " ", sub("\n.*", "", errs[[id]])) else ""
  if (nchar(note) > 80) note <- paste0(substr(note, 1, 77), "...")
  up <- script_uptime(id, 30); up <- if (is.na(up)) "&#8212;" else paste0(up, "%")
  md <- c(md, sprintf("| %s | `%s` | %.1fs | %s | %s |",
                      emoji(script_status[[id]]), id, durs[[id]] %||% 0, up, note))
}
if (!length(ids)) md <- c(md, "| | _(no scripts in `R/` yet)_ | | | |")
writeLines(md, "STATUS.md")

# --- status/badge.json : shields.io endpoint badge --------------------------
all_green <- length(fail_ids) == 0 && length(ids) > 0
writeLines(toJSON(list(
  schemaVersion = 1L, label = "ETL",
  message = if (!length(ids)) "no scripts"
            else if (all_green) sprintf("%d/%d green", length(ids), length(ids))
            else sprintf("%d failing", length(fail_ids)),
  color = if (all_green) "brightgreen" else if (!length(ids)) "lightgrey" else "red"),
  auto_unbox = TRUE), file.path(ST, "badge.json"))

# NB: README.md is NOT rewritten here. The health board is published to the
# unprotected `status` branch (the bot cannot push to protected `main`), and the
# README on `main` embeds status/health.svg + status/badge.json from that branch
# via static raw URLs. So this script only writes the artifacts under status/ + the
# per-script STATUS.md, which the workflow's publish step pushes to `status`.

cat(sprintf("render: %d ok / %d failed, %d script(s) -> status/health.svg, STATUS.md, badge.json\n",
            sum(stat == "SUCCESS"), length(fail_ids), length(ids)))
