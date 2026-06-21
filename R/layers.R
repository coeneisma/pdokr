#' Parse an OGC collections body into a layer registry
#'
#' @param parsed The parsed `{ogc}/collections?f=json` body: a list with a
#'   `collections` element.
#' @param call Calling environment, for error messages.
#'
#' @return A tibble with one row per layer (see `pdok_list_layers()`).
#' @noRd
parse_collections <- function(parsed, call = rlang::caller_env()) {
  cols <- parsed$collections %||% list()

  rows <- lapply(cols, function(co) {
    id <- co$id %||% NA_character_
    if (is.na(id)) {
      return(NULL)
    }

    crs_codes <- vapply(
      co$crs %||% list(),
      function(u) {
        v <- parse_content_crs(u)
        if (is.null(v)) NA_integer_ else v
      },
      integer(1)
    )

    bb <- as.numeric(unlist(co$extent$spatial$bbox %||% list()))
    if (length(bb) == 6L) {
      bb <- bb[c(1, 2, 4, 5)]
    }
    if (length(bb) != 4L) {
      bb <- rep(NA_real_, 4L)
    }
    storage <- parse_content_crs(co$storageCrs)

    tibble::tibble(
      layer       = id,
      title       = co$title %||% NA_character_,
      description = co$description %||% NA_character_,
      crs         = list(crs_codes),
      storage_crs = storage %||% NA_integer_,
      bbox        = list(stats::setNames(bb, c("xmin", "ymin", "xmax", "ymax")))
    )
  })

  rows <- Filter(Negate(is.null), rows)

  if (length(rows) == 0L) {
    return(tibble::tibble(
      layer       = character(),
      title       = character(),
      description = character(),
      crs         = list(),
      storage_crs = integer(),
      bbox        = list()
    ))
  }

  do.call(rbind, rows)
}

#' List the layers within a PDOK dataset
#'
#' Lists the layers (OGC API Features collections) offered by a dataset. The
#' result is cached for the session.
#'
#' @param dataset A dataset id from [pdok_list_datasets()] (e.g.
#'   `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.
#' @param refresh If `TRUE`, ignore the session cache and fetch again.
#'
#' @return A [tibble][tibble::tibble] with one row per layer and the columns
#'   `layer` (the identifier passed to `pdok_read()`), `title`, `description`,
#'   `crs` (a list-column of available EPSG codes), `storage_crs` (the EPSG code
#'   the data is stored in), and `bbox` (a list-column of named numeric extents
#'   `c(xmin, ymin, xmax, ymax)` in CRS84).
#' @seealso [pdok_search_layers()] to filter this list,
#'   [pdok_list_datasets()] for the datasets.
#' @examples
#' \donttest{
#' pdok_list_layers("cbs/gebiedsindelingen")
#' }
#' @export
pdok_list_layers <- function(dataset, refresh = FALSE) {
  resolved <- resolve_dataset(dataset)
  if (is.null(resolved$ogc)) {
    cli::cli_abort(c(
      "{.arg dataset} has no OGC API Features endpoint.",
      "i" = "Listing layers of WFS-only datasets is not supported; pass an OGC dataset id or base URL."
    ))
  }

  ogc <- resolved$ogc
  key <- paste0("collections:", ogc)
  if (!refresh) {
    cached <- cache_get(key)
    if (!is.null(cached)) {
      return(cached)
    }
  }

  resp <- pdok_perform(
    pdok_request(paste0(ogc, "/collections"), query = list(f = "json"))
  )
  layers <- parse_collections(httr2::resp_body_json(resp))
  cache_set(key, layers)
  layers
}

#' Search the layers within a PDOK dataset
#'
#' Filters the layers from [pdok_list_layers()] by a case-insensitive partial
#' match against each layer's identifier, title, and description.
#'
#' @param dataset A dataset id from [pdok_list_datasets()] (e.g.
#'   `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.
#' @param query A single non-empty string to search for, e.g. `"gemeente"`.
#' @param refresh If `TRUE`, ignore the session cache and fetch again.
#'
#' @return A [tibble][tibble::tibble] with the same columns as
#'   [pdok_list_layers()], containing only the matching rows (zero rows when
#'   nothing matches).
#' @seealso [pdok_list_layers()] for the full list.
#' @examples
#' \donttest{
#' pdok_search_layers("cbs/gebiedsindelingen", "gemeente")
#' }
#' @export
pdok_search_layers <- function(dataset, query, refresh = FALSE) {
  if (!rlang::is_string(query) || !nzchar(query)) {
    cli::cli_abort("{.arg query} must be a single non-empty string.")
  }

  layers <- pdok_list_layers(dataset, refresh = refresh)
  haystack <- tolower(paste(layers$layer, layers$title, layers$description))
  keep <- grepl(tolower(query), haystack, fixed = TRUE)
  layers[keep, , drop = FALSE]
}
