# Internal: format a datetime argument for the OGC `datetime` parameter.
# An integer year becomes a representative instant within that year (1 July, so
# it falls inside annual validity periods such as CBS boundaries); a string is
# passed through (an instant or an OGC interval such as "2020-01-01/2025-12-31").
format_datetime <- function(x, call = rlang::caller_env()) {
  if (is.numeric(x) && length(x) == 1L && !is.na(x)) {
    if (x <= 0 || x != round(x)) {
      cli::cli_abort(
        "{.arg datetime} year must be a single positive whole number (e.g. {.val {2026}}).",
        call = call
      )
    }
    return(sprintf("%04d-07-01T00:00:00Z", as.integer(x)))
  }
  if (is.character(x) && length(x) == 1L && nzchar(x)) {
    return(x)
  }
  cli::cli_abort(
    "{.arg datetime} must be a single year (e.g. {.val {2026}}), an OGC datetime string, or an interval such as {.val {\"2020-01-01/2025-12-31\"}}.",
    call = call
  )
}

# Internal: limits within which a point `filter_by` is also sent to the server
# as a CQL2 S_INTERSECTS. Measured on the BAG: 11 points in a city-center
# bbox answer in ~1.5 s and 162 points in a city bbox in ~16 s, but 758
# points in a province bbox time out, because the server tests every point
# against every candidate in the bbox. Beyond these limits the plain bbox
# request is cheaper and safer.
pdok_point_filter_max_points <- 200L
pdok_point_filter_max_extent <- 0.25 # degrees, in both lon and lat

# Internal: a CQL2 S_INTERSECTS clause for a point-only `filter_by`, or NULL
# when the geometry is not points, the predicate cannot use it, or the set is
# too large to be fast on the server.
points_cql_filter <- function(filter_by, predicate, call = rlang::caller_env()) {
  if (is.null(filter_by) || identical(predicate, "disjoint")) {
    return(NULL)
  }
  geom <- sf::st_geometry(filter_by)
  if (length(geom) == 0L || is.na(sf::st_crs(geom))) {
    return(NULL)
  }
  types <- unique(as.character(sf::st_geometry_type(geom)))
  if (!all(types %in% c("POINT", "MULTIPOINT"))) {
    return(NULL)
  }
  pts <- sf::st_transform(geom, 4326)
  coords <- sf::st_coordinates(pts)[, c("X", "Y"), drop = FALSE]
  coords <- unique(coords[stats::complete.cases(coords), , drop = FALSE])
  if (nrow(coords) == 0L || nrow(coords) > pdok_point_filter_max_points) {
    return(NULL)
  }
  if (diff(range(coords[, 1])) > pdok_point_filter_max_extent ||
      diff(range(coords[, 2])) > pdok_point_filter_max_extent) {
    return(NULL)
  }
  fmt <- function(v) formatC(v, digits = 7, format = "f", drop0trailing = TRUE)
  sprintf(
    "S_INTERSECTS(geometry, MULTIPOINT (%s))",
    paste0("(", fmt(coords[, 1]), " ", fmt(coords[, 2]), ")", collapse = ", ")
  )
}

# Internal: read a layer over OGC API Features (paginated, with an optional
# per-page spatial clip so max_features applies to the kept features).
read_ogc <- function(ogc, layer, bbox, datetime, max_features,
                     filter_by = NULL, predicate = "intersects",
                     filter = NULL, call = rlang::caller_env()) {
  # When clipping, fetch full pages and let paginate_ogc stop on the kept
  # count; otherwise the page size can be capped at max_features.
  page_size <- if (!is.null(filter_by) || is.null(max_features)) {
    1000L
  } else {
    min(1000L, max_features)
  }
  query <- list(f = "json", limit = page_size)
  if (!is.null(bbox)) {
    query$bbox <- paste(as_bbox_crs84(bbox, call = call), collapse = ",")
  }
  if (!is.null(datetime)) {
    query$datetime <- format_datetime(datetime, call = call)
  }

  # A filter renders to one CQL2 string, or to several when a pdok_where()
  # holds a long %in% (each batch is a complete standalone filter).
  filters <- if (is.null(filter)) NULL else filter_queries(filter, call = call)
  if (any(nchar(filters) > 30000L)) {
    cli::cli_abort(
      c(
        "The {.arg filter} expression is too long to send as a request URL.",
        "i" = "PDOK drops over-long URLs without a response (measured limit ~33KB).",
        "i" = "Use {.fn pdok_where} with {.code %in%} (long value lists are batched automatically), or split the request yourself."
      ),
      call = call
    )
  }

  process <- if (!is.null(filter_by)) {
    function(page) pdok_filter_by(page, filter_by, predicate = predicate)
  } else {
    NULL
  }

  # A small set of points is also sent as a server-side S_INTERSECTS, so
  # "the features these points fall in" downloads those features instead of
  # everything in their bounding box. The exact clip above still applies.
  spatial <- points_cql_filter(filter_by, predicate, call = call)
  if (!is.null(spatial)) {
    filters <- if (length(filters) == 0L) {
      spatial
    } else {
      paste0("(", filters, ") AND ", spatial)
    }
  }

  url <- paste0(ogc, "/collections/", layer, "/items")
  out <- tryCatch(
    read_ogc_filters(url, query, filters, max_features, process, call = call),
    pdokr_http_error = function(cnd) {
      # A server that does not accept the spatial clause (no CQL2, or a
      # differently named geometry field) answers 400; fall back to the plain
      # bbox request. A user-supplied filter that is itself invalid fails
      # again in the retry, with its own message.
      if (is.null(spatial) || !identical(cnd$status, 400L)) {
        rlang::cnd_signal(cnd)
      }
      plain <- if (is.null(filter)) NULL else filter_queries(filter, call = call)
      read_ogc_filters(url, query, plain, max_features, process, call = call)
    }
  )
  out
}

# Internal: perform the paginated items request(s) for zero, one or several
# complete CQL2 filter strings (several when a pdok_where() batches a long
# %in%), unioning the batches.
read_ogc_filters <- function(url, query, filters, max_features, process,
                             call = rlang::caller_env()) {
  if (length(filters) <= 1L) {
    if (length(filters) == 1L) {
      query$filter <- filters
    }
    return(paginate_ogc(
      url, query = query, max_features = max_features,
      process = process, call = call
    ))
  }

  # Batched filters: one request cycle per batch, unioned. The batches are
  # disjoint value sets, so no deduplication is needed. The number of batches
  # is known up front, so this bar can show an ETA; the per-batch spinner is
  # switched off in favour of it.
  parts <- list()
  n_kept <- 0L
  page <- NULL
  progress <- show_progress()
  if (progress) {
    cli::cli_progress_bar(
      total = length(filters),
      format = paste0(
        "{cli::pb_spin} Downloading PDOK features: ",
        "batch {cli::pb_current}/{cli::pb_total}, {n_kept} fetched | ",
        "ETA {cli::pb_eta}"
      ),
      clear = TRUE
    )
  }
  for (f in filters) {
    q <- query
    q$filter <- f
    remaining <- if (is.null(max_features)) NULL else max_features - n_kept
    page <- paginate_ogc(
      url, query = q, max_features = remaining,
      process = process, progress = FALSE, call = call
    )
    if (nrow(page) > 0L) {
      parts[[length(parts) + 1L]] <- page
      n_kept <- n_kept + nrow(page)
    }
    if (progress) cli::cli_progress_update()
    if (!is.null(max_features) && n_kept >= max_features) break
  }
  if (progress) cli::cli_progress_done()

  out <- rbind_sf(parts) %||% page # all batches empty: a 0-row sf
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
#'   municipality), but points work too: filtering an area layer by points
#'   returns the features that contain them (for example the municipality or
#'   building each address falls in). A small set of points (up to 200, within
#'   roughly 20 km of each other) is also sent to the server as a spatial
#'   CQL2 filter, so only the features touching those points are downloaded
#'   rather than everything in their bounding box.
#' @param predicate Spatial predicate for `filter_by`, passed to
#'   [pdok_filter_by()] (default `"intersects"`). See its *Spatial predicates*
#'   section for the available options, and [sf::geos_binary_pred] for their
#'   definitions.
#' @param datetime Optional temporal filter: a single year (e.g. `2026`, mapped
#'   to a mid-year instant), an OGC datetime string, or an interval such as
#'   `"2020-01-01/2025-12-31"`.
#' @param filter Optional server-side attribute filter: a
#'   [pdok_where()] expression (R syntax, translated for you), or a single
#'   [CQL2](https://www.ogc.org/standards/cql2/) text string passed to the
#'   service unchanged, e.g. `"postcode = '3811MZ'"`. Every PDOK dataset with
#'   OGC API Features supports CQL2, but each layer only allows filtering on
#'   a selected set of fields: see [pdok_list_queryables()]. A filter on any
#'   other field is rejected by the server with a clear error, never silently
#'   ignored.
#' @param crs Optional output CRS as an EPSG code (e.g. `28992` for RD New).
#'   `NULL` keeps the source CRS.
#' @param max_features Optional cap on the number of features returned.
#'
#' @return An [sf][sf::st_sf] object with one row per feature, the layer's
#'   attribute columns, and a geometry column. A zero-row `sf` is returned (with
#'   a warning) when nothing matches.
#' @seealso [pdok_list_layers()] to find layer ids, [pdok_list_queryables()]
#'   for the fields a `filter` expression can use.
#' @examplesIf pdokr:::pdok_reachable()
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
                      filter = NULL, crs = NULL, max_features = NULL) {
  if (!rlang::is_string(layer) || !nzchar(layer)) {
    cli::cli_abort("{.arg layer} must be a single non-empty string.")
  }
  if (!is.null(filter_by) && !inherits(filter_by, c("sf", "sfc"))) {
    cli::cli_abort("{.arg filter_by} must be an {.cls sf} or {.cls sfc} object.")
  }
  if (!is.null(filter) && !inherits(filter, "pdok_where") &&
      (!rlang::is_string(filter) || !nzchar(filter))) {
    cli::cli_abort(
      "{.arg filter} must be a single non-empty CQL2 string or a {.fn pdok_where} expression."
    )
  }
  check_count(max_features, "max_features", allow_null = TRUE)
  if (!is.null(crs)) {
    check_crs(crs)
  }

  # filter_by drives the cheap server-side bbox pre-filter (an explicit bbox wins).
  server_bbox <- bbox %||% filter_by

  resolved <- resolve_dataset(dataset)
  out <- tryCatch(
    read_ogc(
      resolved$ogc, layer, server_bbox, datetime, max_features,
      filter_by = filter_by, predicate = predicate, filter = filter
    ),
    error = function(cnd) abort_not_features(resolved$id, resolved$ogc, cnd)
  )

  if (nrow(out) == 0L) {
    cli::cli_warn(c(
      "No features were returned for layer {.val {layer}}.",
      "i" = "Check the layer id, and any {.arg bbox}, {.arg filter_by}, {.arg filter} or {.arg datetime} filter."
    ))
    return(out)
  }

  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  out
}
