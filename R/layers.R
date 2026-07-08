# Internal: the date part of an ISO datetime string, or NA.
as_extent_date <- function(x) {
  if (is.null(x) || !is.character(x) || length(x) != 1L || !nzchar(x)) {
    return(as.Date(NA))
  }
  as.Date(substr(x, 1L, 10L))
}

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

    ivl <- co$extent$temporal$interval
    pair <- if (length(ivl) >= 1L) ivl[[1]] else list()
    start_date <- as_extent_date(if (length(pair) >= 1L) pair[[1]] else NULL)
    end_date <- as_extent_date(if (length(pair) >= 2L) pair[[2]] else NULL)

    tibble::tibble(
      layer       = id,
      title       = co$title %||% NA_character_,
      description = co$description %||% NA_character_,
      start_date  = start_date,
      end_date    = end_date,
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
      start_date  = as.Date(character()),
      end_date    = as.Date(character()),
      crs         = list(),
      storage_crs = integer(),
      bbox        = list()
    ))
  }

  do.call(rbind, rows)
}

#' List the layers within a PDOK dataset
#'
#' Lists the layers (OGC API Features collections) offered by a dataset.
#'
#' @param dataset A dataset id from [pdok_list_datasets()] (e.g.
#'   `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.
#'
#' @return A [tibble][tibble::tibble] with one row per layer and the columns
#'   `dataset` (the dataset id, echoing the input so each row works directly
#'   with [pdok_read()]), `layer` (the layer identifier), `title`,
#'   `description`, `start_date` and `end_date` (the temporal extent the layer
#'   covers, as `Date`s; `end_date` is `NA` when the layer is ongoing), `crs` (a
#'   list-column of available EPSG codes), `storage_crs` (the EPSG code the data
#'   is stored in), and `bbox` (a list-column of named numeric extents
#'   `c(xmin, ymin, xmax, ymax)` in CRS84).
#' @seealso [pdok_search_layers()] to filter this list,
#'   [pdok_list_datasets()] for the datasets.
#' @examples
#' \donttest{
#' pdok_list_layers("cbs/gebiedsindelingen")
#' }
#' @export
pdok_list_layers <- function(dataset) {
  resolved <- resolve_dataset(dataset)
  ogc <- resolved$ogc
  layers <- tryCatch(
    {
      resp <- pdok_perform(
        pdok_request(paste0(ogc, "/collections"), query = list(f = "json"))
      )
      parse_collections(httr2::resp_body_json(resp))
    },
    error = function(cnd) abort_not_features(resolved$id, ogc, cnd)
  )
  # Echo the dataset so each row is self-contained for pdok_read(dataset, layer).
  tibble::add_column(
    layers,
    dataset = rep(resolved$id, nrow(layers)),
    .before = 1L
  )
}

#' Search the layers within a PDOK dataset
#'
#' Filters the layers from [pdok_list_layers()] by a case-insensitive partial
#' match against each layer's identifier, title, and description.
#'
#' @param dataset A dataset id from [pdok_list_datasets()] (e.g.
#'   `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.
#' @param query A single non-empty string to search for, e.g. `"gemeente"`.
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
pdok_search_layers <- function(dataset, query) {
  if (!rlang::is_string(query) || !nzchar(query)) {
    cli::cli_abort("{.arg query} must be a single non-empty string.")
  }

  layers <- pdok_list_layers(dataset)
  haystack <- tolower(paste(layers$layer, layers$title, layers$description))
  keep <- grepl(tolower(query), haystack, fixed = TRUE)
  layers[keep, , drop = FALSE]
}
