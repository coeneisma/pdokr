# Discovery of the fields a CQL2 `filter` expression can use, via the OGC API
# Features "queryables" endpoint (ogcapi-features-3).

#' Parse an OGC queryables body into a tibble
#'
#' @param parsed The parsed `{ogc}/collections/{layer}/queryables?f=json` body:
#'   a JSON Schema object whose `properties` are the queryable fields.
#'
#' @return A tibble with one row per queryable field (see
#'   `pdok_list_queryables()`).
#' @noRd
parse_queryables <- function(parsed) {
  props <- parsed$properties %||% list()

  rows <- lapply(names(props), function(nm) {
    p <- props[[nm]]
    tibble::tibble(
      queryable   = nm,
      # The geometry field carries a `format` ("geometry-point", ...) instead
      # of a JSON Schema `type`.
      type        = p$type %||% p$format %||% NA_character_,
      description = p$description %||% NA_character_
    )
  })

  if (length(rows) == 0L) {
    return(tibble::tibble(
      queryable   = character(),
      type        = character(),
      description = character()
    ))
  }
  do.call(rbind, rows)
}

# Internal: fetch and parse the queryables of one layer, or NULL when the
# service answers 404 (the layer does not exist, or the dataset serves no
# features at all).
fetch_queryables <- function(ogc, layer, call = rlang::caller_env()) {
  req <- pdok_request(
    paste0(ogc, "/collections/", layer, "/queryables"),
    query = list(f = "json")
  )
  req <- httr2::req_error(req, is_error = function(resp) {
    status <- httr2::resp_status(resp)
    status >= 400L && status != 404L
  })
  resp <- pdok_perform(req, call = call)
  if (httr2::resp_status(resp) == 404L) {
    return(NULL)
  }
  parse_queryables(httr2::resp_body_json(resp))
}

#' List the fields a server-side filter can use
#'
#' Retrieves the *queryables* of a layer: the fields that a
#' CQL2 `filter` expression (see the `filter` argument of [pdok_read()] and
#' [pdok_where()]) is allowed to reference. Every PDOK dataset with OGC API
#' Features supports CQL2 filtering, but the set of filterable fields is
#' chosen per layer and is often a small subset of the layer's attributes, so
#' check it before writing a filter.
#'
#' @param dataset A dataset id from [pdok_list_datasets()], or a raw OGC API
#'   base URL.
#' @param layer A layer id from [pdok_list_layers()].
#'
#' @return A tibble with one row per filterable field and columns `queryable`,
#'   `type`, and `description`.
#' @seealso [pdok_read()] and [pdok_where()] to use these fields in a filter;
#'   `pdok_list_layers(dataset, queryables = TRUE)` for the queryables of
#'   every layer of a dataset at once.
#' @examples
#' \donttest{
#' pdok_list_queryables("kadaster/bag", "adres")
#'
#' # Often only a few of a layer's fields are filterable
#' pdok_list_queryables("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd")
#' }
#' @export
pdok_list_queryables <- function(dataset, layer) {
  if (!rlang::is_string(layer) || !nzchar(layer)) {
    cli::cli_abort("{.arg layer} must be a single non-empty string.")
  }
  resolved <- resolve_dataset(dataset)

  out <- fetch_queryables(resolved$ogc, layer)
  if (is.null(out)) {
    cli::cli_abort(c(
      "No queryables found for layer {.val {layer}} of dataset {.val {resolved$id}} (HTTP 404).",
      "i" = "Check the layer id with {.fn pdok_list_layers}.",
      "i" = "A dataset that serves tiles or coverages instead of features has no queryables; {.pkg pdokr} reads vector features only."
    ))
  }
  out
}
