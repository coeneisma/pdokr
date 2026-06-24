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
#' Features and/or WFS endpoints it maps to. A registry id is looked up in the
#' live index so the correct OGC API version (`v1`, `v2`, ...) is used.
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

  # Raw URL: classify by shape (any OGC version, or WFS).
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

  # Registry id: look up its OGC URL in the live index, so the right version
  # (v1, v2, ...) is used rather than an assumed one.
  id <- gsub("^/+|/+$", "", dataset)
  reg <- fetch_index(call = call)
  hit <- reg[reg$id == id, ]
  if (nrow(hit) >= 1L) {
    return(list(id = id, ogc = hit$ogc_url[[1]], wfs = NULL, services = "ogc"))
  }

  cli::cli_abort(
    c(
      "Unknown dataset {.val {id}}.",
      "i" = "See {.fn pdok_search_datasets} for available ids, or pass a full OGC API base URL."
    ),
    call = call
  )
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
    # Find the OGC API Features root link (any version: v1, v2, ...).
    href <- NULL
    for (lnk in api$links %||% list()) {
      h <- lnk$href %||% ""
      if (grepl("/ogc/v\\d+/?$", h)) {
        href <- h
        break
      }
    }
    if (is.null(href)) {
      return(NULL)
    }

    id <- sub("/ogc/v\\d+/?$", "", sub("^https?://api\\.pdok\\.nl/", "", href))
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

#' Fetch the PDOK dataset registry
#'
#' Retrieves and parses `https://api.pdok.nl/index.json`. Requires a network
#' connection; raises an informative error when PDOK cannot be reached.
#'
#' @param call Calling environment, for messages.
#'
#' @return A registry tibble (see `parse_index()`).
#' @noRd
fetch_index <- function(call = rlang::caller_env()) {
  resp <- pdok_perform(pdok_request(pdok_base_urls$index), call = call)
  parse_index(httr2::resp_body_json(resp))
}
