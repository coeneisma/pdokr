# Central configuration of every PDOK endpoint URL.
#
# This is the single place to change if PDOK migrates hosts again (as it did
# from `geodata.nationaalgeoregister.nl` to `api.pdok.nl`). All other code
# resolves endpoints through the helpers in this file.

# Internal: base URLs for the PDOK services the package talks to.
#
# - index: the JSON index of all OGC API datasets at api.pdok.nl
# - locatieserver: base for the PDOK Locatieserver (geocoding)
pdok_base_urls <- list(
  index         = "https://api.pdok.nl/index.json",
  locatieserver = "https://api.pdok.nl/bzk/locatieserver/search/v3_1"
)

#' Resolve a dataset reference to its OGC API endpoint
#'
#' Accepts either a registry id of the form `"owner/dataset"` (as returned by
#' `pdok_search_datasets()`) or a raw OGC API base URL. A registry id is looked
#' up in the live index so the correct OGC API version (`v1`, `v2`, ...) is used.
#'
#' @param dataset A single string: a registry id (e.g.
#'   `"cbs/gebiedsindelingen"`) or a full OGC API base URL.
#' @param call The calling environment, for error messages.
#'
#' @return A list with elements `id` and `ogc` (the OGC API base URL).
#' @noRd
resolve_dataset <- function(dataset, call = rlang::caller_env()) {
  if (!rlang::is_string(dataset) || !nzchar(dataset)) {
    cli::cli_abort(
      "{.arg dataset} must be a single non-empty string.",
      call = call
    )
  }

  # Raw URL: accept OGC; reject WFS (pdokr is an OGC API Features client).
  if (grepl("^https?://", dataset, ignore.case = TRUE)) {
    if (grepl("service\\.pdok\\.nl|[?&]service=wfs|/wfs", dataset, ignore.case = TRUE)) {
      cli::cli_abort(
        c(
          "{.arg dataset} looks like a WFS URL, which {.pkg pdokr} does not read.",
          "i" = "Use the dataset's OGC API Features service instead, or read WFS directly with {.fn sf::read_sf}."
        ),
        call = call
      )
    }
    return(list(id = dataset, ogc = sub("/+$", "", dataset)))
  }

  # Registry id: look up its OGC URL in the live index, so the right version
  # (v1, v2, ...) is used rather than an assumed one.
  id <- gsub("^/+|/+$", "", dataset)
  reg <- fetch_index(call = call)
  hit <- reg[reg$id == id, ]
  if (nrow(hit) >= 1L) {
    return(list(id = id, ogc = hit$ogc_url[[1]]))
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
