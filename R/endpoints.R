# Central configuration of every PDOK endpoint URL.
#
# This is the single place to change if PDOK migrates hosts again (as it did
# from `geodata.nationaalgeoregister.nl` to `api.pdok.nl`). All other code
# resolves endpoints through the helpers in this file.

# Internal: base URLs for the PDOK services the package talks to.
#
# - index: the JSON index of all OGC API datasets at api.pdok.nl
# - ogc_host: host for OGC API Features datasets (id is inserted as
#   `{ogc_host}/{owner}/{dataset}/ogc/v1`)
# - wfs_host: host for WFS services (fallback path)
# - locatieserver: base for the PDOK Locatieserver (geocoding)
pdok_base_urls <- list(
  index         = "https://api.pdok.nl/index.json",
  ogc_host      = "https://api.pdok.nl",
  wfs_host      = "https://service.pdok.nl",
  locatieserver = "https://api.pdok.nl/bzk/locatieserver/search/v3_1"
)

#' Resolve a dataset reference to its service endpoints
#'
#' Accepts either a registry id of the form `"owner/dataset"` (as returned by
#' `pdok_search_datasets()`) or a raw service URL, and returns the OGC API
#' Features and/or WFS endpoints it maps to.
#'
#' @param dataset A single string: a registry id (e.g.
#'   `"cbs/gebiedsindelingen"`) or a full service URL.
#' @param call The calling environment, for error messages.
#'
#' @return A list with elements `id`, `ogc` (OGC API base URL or `NULL`),
#'   `wfs` (WFS base URL or `NULL`), and `services` (a character vector of the
#'   available service types).
#' @noRd
resolve_dataset <- function(dataset, call = rlang::caller_env()) {
  if (!rlang::is_string(dataset) || !nzchar(dataset)) {
    cli::cli_abort(
      "{.arg dataset} must be a single non-empty string.",
      call = call
    )
  }

  # Raw URL: classify by shape.
  if (grepl("^https?://", dataset, ignore.case = TRUE)) {
    is_wfs <- grepl("service\\.pdok\\.nl|[?&]service=wfs|/wfs", dataset,
                    ignore.case = TRUE)
    if (is_wfs) {
      return(list(
        id = dataset, ogc = NULL, wfs = dataset, services = "wfs"
      ))
    }
    ogc <- sub("/+$", "", dataset)
    return(list(id = dataset, ogc = ogc, wfs = NULL, services = "ogc"))
  }

  # Registry id like "owner/dataset": always an OGC API dataset.
  id <- gsub("^/+|/+$", "", dataset)
  ogc <- paste0(pdok_base_urls$ogc_host, "/", id, "/ogc/v1")
  list(id = id, ogc = ogc, wfs = NULL, services = "ogc")
}

#' Parse the PDOK API index into a dataset registry
#'
#' Turns the parsed body of `https://api.pdok.nl/index.json` into a tidy
#' registry of OGC API Features datasets. Pure (no network), so it can be
#' tested against a fixture.
#'
#' @param parsed The parsed `index.json` body: a list with an `apis` element,
#'   each entry holding `title`, `description`, `keywords`, and `links`.
#'
#' @return A tibble with one row per OGC API dataset and columns `id`, `name`,
#'   `description`, `keywords` (a list-column of character vectors), `services`,
#'   `owner`, and `ogc_url`.
#' @noRd
parse_index <- function(parsed) {
  apis <- parsed$apis %||% list()

  rows <- lapply(apis, function(api) {
    # Find the OGC API Features root link.
    href <- NULL
    for (lnk in api$links %||% list()) {
      h <- lnk$href %||% ""
      if (grepl("/ogc/v1/?$", h)) {
        href <- h
        break
      }
    }
    if (is.null(href)) {
      return(NULL)
    }

    id <- sub("/ogc/v1/?$", "", sub("^https?://api\\.pdok\\.nl/", "", href))
    owner <- sub("/.*$", "", id)

    kw <- api$keywords %||% character()
    kw <- as.character(unlist(kw, use.names = FALSE))

    tibble::tibble(
      id          = id,
      name        = api$title %||% NA_character_,
      description = api$description %||% NA_character_,
      keywords    = list(kw),
      services    = "ogc",
      owner       = owner,
      ogc_url     = sub("/+$", "", href)
    )
  })

  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0L) {
    return(tibble::tibble(
      id          = character(),
      name        = character(),
      description = character(),
      keywords    = list(),
      services    = character(),
      owner       = character(),
      ogc_url     = character()
    ))
  }

  do.call(rbind, rows)
}

#' Fetch the PDOK dataset registry (live, session-cached)
#'
#' Retrieves and parses `https://api.pdok.nl/index.json`, caching the result for
#' the session. On a network or parse failure it warns and falls back to the
#' snapshot bundled with the package.
#'
#' @param force If `TRUE`, bypass the session cache and fetch afresh.
#' @param call Calling environment, for messages.
#'
#' @return A registry tibble (see `parse_index()`).
#' @noRd
fetch_index <- function(force = FALSE, call = rlang::caller_env()) {
  key <- "index"
  if (!force) {
    cached <- cache_get(key)
    if (!is.null(cached)) {
      return(cached)
    }
  }

  reg <- tryCatch(
    {
      resp <- pdok_perform(pdok_request(pdok_base_urls$index), call = call)
      parse_index(httr2::resp_body_json(resp))
    },
    error = function(cnd) {
      cli::cli_warn(
        c(
          "Could not fetch the live PDOK dataset index; using the bundled snapshot.",
          "i" = "The snapshot may be out of date; retry later for the current list."
        )
      )
      pdok_datasets_snapshot
    }
  )

  cache_set(key, reg)
  reg
}
