# CKAN API helpers for sg-ogd-data dataset scripts.
#
# A dataset script in R/ sources this file and uses these helpers to push its data
# to the SG CKAN instance. Authentication is an API token taken from the
# environment variable CKAN_API_KEY (a GitHub Actions secret in CI; export it in
# your shell to test locally). The target instance is CKAN_URL, defaulting to the
# cynkra-hosted https://ogd.cynkra.dev.
#
#   source(file.path(Sys.getenv("SGOGD_ROOT", "."), "tools", "ckan.R"))
#   ckan_upload_csv(
#     dataset  = "wetterdaten-stadt-sg",   # CKAN dataset (package) name, must exist
#     resource = "Aktuelle Messwerte",     # resource name within the dataset
#     data     = df                        # a data.frame, or a path to a .csv file
#   )
#
# ckan_action() is the low-level escape hatch for any CKAN Action API call.

suppressPackageStartupMessages(library(httr2))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

ckan_base <- function() sub("/+$", "", Sys.getenv("CKAN_URL", "https://ogd.cynkra.dev"))

ckan_token <- function() {
  tok <- Sys.getenv("CKAN_API_KEY", "")
  if (!nzchar(tok)) {
    stop("CKAN_API_KEY is not set - cannot authenticate to CKAN. ",
         "In CI it comes from the repo secret; locally, `export CKAN_API_KEY=...`.")
  }
  tok
}

# Low-level: POST https://<ckan>/api/3/action/<action>. Pass `body` for a JSON
# payload, or `multipart` (a named list) for a file upload. Returns the parsed
# `result`, or stops with CKAN's own error message on failure.
ckan_action <- function(action, body = NULL, multipart = NULL) {
  req <- request(ckan_base()) |>
    req_url_path_append("api", "3", "action", action) |>
    req_headers(Authorization = ckan_token()) |>
    req_user_agent("sg-ogd-data (https://github.com/cynkra/sg-ogd-data)") |>
    req_error(body = function(resp) {
      j <- tryCatch(resp_body_json(resp), error = function(e) NULL)
      j$error$message %||% j$error$`__type` %||% resp_status_desc(resp)
    })
  if (!is.null(multipart)) {
    req <- req_body_multipart(req, !!!multipart)
  } else if (!is.null(body)) {
    req <- req_body_json(req, body)
  }
  resp_body_json(req_perform(req))$result
}

# Find a resource by its display name within a dataset. Returns the resource list
# (with $id) or NULL if the dataset or the named resource does not exist.
ckan_find_resource <- function(dataset, resource) {
  pkg <- tryCatch(ckan_action("package_show", body = list(id = dataset)),
                  error = function(e) NULL)
  if (is.null(pkg)) return(NULL)
  for (r in pkg$resources %||% list()) if (identical(r$name, resource)) return(r)
  NULL
}

# Upload a CSV to CKAN as a named resource on an existing dataset. Find-or-update
# by resource name: creates the resource the first time, patches the file on every
# later run (so the dataset keeps one stable, refreshed resource rather than piling
# up duplicates). A CSV resource triggers XLoader, which loads it into the
# DataStore API automatically. `data` is a data.frame (written to a temp CSV) or a
# path to an existing .csv.
ckan_upload_csv <- function(dataset, resource, data, format = "CSV",
                            description = NULL) {
  path <- if (is.data.frame(data)) {
    p <- tempfile(fileext = ".csv")
    utils::write.csv(data, p, row.names = FALSE, na = "")
    p
  } else {
    if (!file.exists(data)) stop("ckan_upload_csv: file not found: ", data)
    data
  }
  fields <- list(name = resource, format = format,
                 upload = curl::form_file(path))
  if (!is.null(description)) fields$description <- description

  existing <- ckan_find_resource(dataset, resource)
  if (is.null(existing)) {
    fields$package_id <- dataset
    ckan_action("resource_create", multipart = fields)
  } else {
    fields$id <- existing$id
    ckan_action("resource_patch", multipart = fields)
  }
}
