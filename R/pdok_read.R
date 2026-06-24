# Internal: format a datetime argument for the OGC `datetime` parameter.
# An integer year becomes a representative instant within that year (1 July, so
# it falls inside annual validity periods such as CBS boundaries); a string is
# passed through (an instant or an OGC interval such as "2020-01-01/2025-12-31").
format_datetime <- function(x, call = rlang::caller_env()) {
  if (is.numeric(x) && length(x) == 1L && !is.na(x)) {
    return(sprintf("%04d-07-01T00:00:00Z", as.integer(x)))
  }
  if (is.character(x) && length(x) == 1L && nzchar(x)) {
    return(x)
  }
  cli::cli_abort(
    "{.arg datetime} must be a single year (e.g. {.val {2026}}) or an OGC datetime string.",
    call = call
  )
}

# Internal: read a layer over OGC API Features (paginated).
read_ogc <- function(ogc, layer, bbox, datetime, max_features,
                     call = rlang::caller_env()) {
  query <- list(
    f = "json",
    limit = if (is.null(max_features)) 1000L else min(1000L, max_features)
  )
  if (!is.null(bbox)) {
    query$bbox <- paste(as_bbox_crs84(bbox, call = call), collapse = ",")
  }
  if (!is.null(datetime)) {
    query$datetime <- format_datetime(datetime, call = call)
  }

  url <- paste0(ogc, "/collections/", layer, "/items")
  res <- paginate_ogc(url, query = query, max_features = max_features, call = call)
  out <- parse_features(res$pages, res$content_crs, call = call)

  if (!is.null(max_features) && nrow(out) > max_features) {
    out <- out[seq_len(max_features), , drop = FALSE]
  }
  out
}

#' Read a PDOK layer as an sf object
#'
#' Loads a layer from PDOK as a simple feature collection over the OGC API
#' Features service, handling pagination automatically.
#'
#' By default the data is returned in the coordinate reference system the
#' service provides (lon/lat, CRS84, for the OGC path). Set `crs` to receive the
#' data in another CRS; the transformation is done client-side with
#' [sf::st_transform()].
#'
#' @param dataset A dataset id from [pdok_list_datasets()] (e.g.
#'   `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.
#' @param layer A layer id from [pdok_list_layers()].
#' @param bbox Optional server-side bounding-box pre-filter: a numeric vector
#'   `c(xmin, ymin, xmax, ymax)` (assumed CRS84) or an `sf`/`sfc`/`bbox` object
#'   whose extent is used.
#' @param filter_by Optional `sf`/`sfc` geometry to filter the result by. Its
#'   bounding box is used as a cheap server-side pre-filter, and the result is
#'   then filtered exactly with [pdok_filter_by()]. This is the one-call form of
#'   the load-then-filter workflow. It is usually a polygon (e.g. a
#'   municipality), but a point works too: filtering an area layer by a point
#'   returns the feature that contains it (for example the municipality an
#'   address falls in).
#' @param predicate Spatial predicate for `filter_by`, passed to
#'   [pdok_filter_by()] (default `"intersects"`).
#' @param datetime Optional temporal filter: a single year (e.g. `2026`, mapped
#'   to a mid-year instant), an OGC datetime string, or an interval such as
#'   `"2020-01-01/2025-12-31"`.
#' @param crs Optional output CRS as an EPSG code (e.g. `28992` for RD New).
#'   `NULL` keeps the source CRS.
#' @param max_features Optional cap on the number of features returned.
#'
#' @return An [sf][sf::st_sf] object with one row per feature, the layer's
#'   attribute columns, and a geometry column. A zero-row `sf` is returned (with
#'   a warning) when nothing matches.
#' @seealso [pdok_list_layers()] to find layer ids.
#' @examples
#' \donttest{
#' # A whole layer: the Dutch national parks
#' parks <- pdok_read("rvo/nationale-parken-geharmoniseerd", "protectedsite")
#'
#' # Municipalities for 2024, in RD New (EPSG:28992)
#' pdok_read(
#'   "cbs/gebiedsindelingen", "gemeente_gegeneraliseerd",
#'   datetime = 2024, crs = 28992, max_features = 5
#' )
#'
#' # One-call area filter: national parks within the province of Utrecht
#' provinces <- pdok_read(
#'   "cbs/gebiedsindelingen", "provincie_gegeneraliseerd", datetime = 2024
#' )
#' utrecht <- provinces[provinces$statnaam == "Utrecht", ]
#' parks_utrecht <- pdok_read(
#'   "rvo/nationale-parken-geharmoniseerd", "protectedsite",
#'   filter_by = utrecht
#' )
#' }
#' @export
pdok_read <- function(dataset, layer, bbox = NULL, filter_by = NULL,
                      predicate = "intersects", datetime = NULL,
                      crs = NULL, max_features = NULL) {
  if (!rlang::is_string(layer) || !nzchar(layer)) {
    cli::cli_abort("{.arg layer} must be a single non-empty string.")
  }
  if (!is.null(filter_by) && !inherits(filter_by, c("sf", "sfc"))) {
    cli::cli_abort("{.arg filter_by} must be an {.cls sf} or {.cls sfc} object.")
  }
  if (!is.null(max_features) &&
      (!is.numeric(max_features) || length(max_features) != 1L ||
       is.na(max_features) || max_features < 1 || max_features != round(max_features))) {
    cli::cli_abort("{.arg max_features} must be a single positive whole number or {.code NULL}.")
  }

  # filter_by drives the cheap server-side bbox pre-filter (an explicit bbox wins).
  server_bbox <- bbox %||% filter_by

  resolved <- resolve_dataset(dataset)
  out <- read_ogc(resolved$ogc, layer, server_bbox, datetime, max_features)

  if (nrow(out) == 0L) {
    cli::cli_warn(c(
      "No features were returned for layer {.val {layer}}.",
      "i" = "Check the layer id, and any {.arg bbox}, {.arg filter_by} or {.arg datetime} filter."
    ))
    return(out)
  }

  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  if (!is.null(filter_by)) {
    out <- pdok_filter_by(out, filter_by, predicate = predicate)
  }
  out
}
