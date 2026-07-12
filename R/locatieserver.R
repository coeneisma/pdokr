# Geocoding via the PDOK Locatieserver. Self-contained module built on the
# shared httr2 request layer; returns sf so results plug into pdok_read()'s
# filter_by.

# Internal: the result types the Locatieserver exposes (those that hold data).
locatieserver_types <- c(
  "adres", "postcode", "weg", "woonplaats", "gemeente", "provincie",
  "buurt", "wijk", "perceel", "hectometerpaal", "appartementsrecht"
)

#' Parse Locatieserver docs into an sf object
#'
#' Returns every (non-geometry) field the service provides, so the output stays
#' future-proof; the geometry is taken from `geometrie_ll`.
#'
#' @param docs The `response$docs` list from a Locatieserver `free` query.
#' @param call Calling environment, for error messages.
#'
#' @return An `sf` object in CRS84, or a 0-row `sf` when `docs` is empty.
#' @noRd
parse_locatieserver <- function(docs, call = rlang::caller_env()) {
  # Fields that become the geometry (or are Solr internals) are not kept as
  # attribute columns.
  geom_fields <- c("geometrie_ll", "geometrie_rd", "centroide_ll", "centroide_rd")

  empty <- sf::st_sf(
    weergavenaam = character(),
    type = character(),
    geometry = sf::st_sfc(crs = 4326)
  )
  if (length(docs) == 0L) {
    return(empty)
  }

  # Drop any result without a geometry (st_as_sfc() would error on an NA WKT).
  wkt <- vapply(docs, function(d) {
    d$geometrie_ll %||% d$centroide_ll %||% NA_character_
  }, character(1))
  docs <- docs[!is.na(wkt)]
  wkt <- wkt[!is.na(wkt)]
  if (length(docs) == 0L) {
    return(empty)
  }
  geometry <- sf::st_as_sfc(wkt, crs = 4326)

  keys <- unique(unlist(lapply(docs, names)))
  keys <- setdiff(keys, geom_fields)
  keys <- keys[!startsWith(keys, "_")]

  # `score` (free query) and `afstand` (reverse query, distance in meters) are
  # numeric; every other field is kept as a string (a multi-value field is
  # collapsed with "; ").
  numeric_fields <- c("score", "afstand")
  pull <- function(key) {
    if (key %in% numeric_fields) {
      return(vapply(docs, function(d) as.numeric(d[[key]] %||% NA), numeric(1)))
    }
    vapply(docs, function(d) {
      v <- d[[key]]
      if (is.null(v)) NA_character_ else paste(as.character(v), collapse = "; ")
    }, character(1))
  }

  attrs <- tibble::as_tibble(stats::setNames(lapply(keys, pull), keys))

  # Surface the most useful fields first; keep the rest in their original order.
  preferred <- intersect(
    c("weergavenaam", "type", "score", "afstand", "gemeentenaam",
      "woonplaatsnaam", "provincienaam"),
    keys
  )
  attrs <- attrs[, c(preferred, setdiff(keys, preferred)), drop = FALSE]

  sf::st_sf(attrs, geometry = geometry)
}

# Internal: validate an optional `type` against the known result types.
check_locatieserver_type <- function(type, call = rlang::caller_env()) {
  if (!is.null(type) &&
      (!rlang::is_string(type) || !type %in% locatieserver_types)) {
    cli::cli_abort(c(
      "{.arg type} must be one of {.or {.val {locatieserver_types}}}.",
      "x" = "You supplied {.val {type}}."
    ), call = call)
  }
  invisible(type)
}

# Internal: one free-text geocode query -> sf (0+ rows), in the source CRS
# (CRS84). No CRS transform here; the caller applies the output CRS once.
geocode_free_one <- function(query, type, limit, call = rlang::caller_env()) {
  q <- list(q = query, rows = limit, fl = "*,score")
  if (!is.null(type)) {
    q$fq <- paste0("type:", type)
  }
  resp <- pdok_perform(
    pdok_request(paste0(pdok_base_urls$locatieserver, "/free"), query = q),
    call = call
  )
  parse_locatieserver(httr2::resp_body_json(resp)$response$docs, call = call)
}

# Internal: one reverse query (a lon/lat point) -> sf (0+ rows), source CRS.
reverse_one <- function(lon, lat, type, limit, call = rlang::caller_env()) {
  q <- list(lon = lon, lat = lat, rows = limit, fl = "*")
  if (!is.null(type)) {
    q$type <- type
  }
  resp <- pdok_perform(
    pdok_request(paste0(pdok_base_urls$locatieserver, "/reverse"), query = q),
    call = call
  )
  parse_locatieserver(httr2::resp_body_json(resp)$response$docs, call = call)
}

# Internal: bind the per-input result sfs (each already carrying its `id_col`),
# warn about inputs that matched nothing, move the id column first, and apply
# the optional output CRS. `results[[1]]` is an empty sf, returned when nothing
# matched at all.
combine_geocode <- function(results, id_col, crs, call = rlang::caller_env()) {
  matched <- vapply(results, function(x) nrow(x) > 0L, logical(1))
  n <- length(results)
  if (any(!matched)) {
    cli::cli_warn(c(
      "No result for {sum(!matched)} of {n} input{?s}.",
      "i" = "The {.field {id_col}} column maps each row back to its input."
    ), call = call)
  }
  if (!any(matched)) {
    return(results[[1]])
  }
  out <- rbind_sf(results[matched])
  geom_col <- attr(out, "sf_column")
  out <- out[, c(id_col, setdiff(names(out), c(id_col, geom_col)), geom_col)]
  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  out
}

#' Geocode addresses or place names with the PDOK Locatieserver
#'
#' Looks up addresses, place names, postcodes, municipalities, provinces and
#' more through the 'PDOK' Locatieserver, returning the results as a simple
#' feature collection. Point geometry is returned for addresses and places, and
#' boundary polygons for administrative areas such as municipalities — so a
#' result drops straight into the `filter_by` argument of [pdok_read()].
#'
#' `query` may be a vector, geocoding many locations in one call (for example a
#' column of addresses). Each result row carries a `query` column with the input
#' it came from, so the output maps back to the input even when a query returns
#' several candidates or none.
#'
#' @param query A character vector of one or more non-empty search strings, e.g.
#'   `"Park Arenberg 88, De Bilt"`.
#' @param type Optional result type to restrict to, one of `"adres"`,
#'   `"postcode"`, `"weg"`, `"woonplaats"`, `"gemeente"`, `"provincie"`,
#'   `"buurt"`, `"wijk"`, `"perceel"`, `"hectometerpaal"`, or
#'   `"appartementsrecht"`. `NULL` (the default) returns the best matches of any
#'   type, ranked by the service's relevance `score`. Use `type` to
#'   disambiguate names that exist in several categories (for example
#'   `"Utrecht"` is both a municipality and a province).
#' @param crs Optional output CRS as an EPSG code (e.g. `28992`). `NULL` keeps
#'   the source CRS (CRS84, lon/lat).
#' @param limit Maximum number of results to return per query (default 1).
#'
#' @return An [sf][sf::st_sf] object with one row per match and a `query` column
#'   identifying the input each row came from. All non-geometry fields the
#'   service returns are kept as columns (with `query`, `weergavenaam`, `type`,
#'   `score`, and the administrative names first); the geometry is a point for
#'   addresses and places and a polygon for administrative areas. Queries that
#'   match nothing are dropped (with a warning), so the result can have fewer
#'   rows than `query` has elements; a zero-row `sf` is returned when nothing
#'   matches at all.
#' @seealso [pdok_reverse_geocode()] for the reverse lookup (coordinates to the
#'   nearest address), and [pdok_read()], whose `filter_by` argument accepts the
#'   result.
#' @examples
#' \donttest{
#' # An address: a point
#' pdok_geocode("Park Arenberg 88, De Bilt")
#'
#' # A municipality: a boundary polygon
#' pdok_geocode("De Bilt", type = "gemeente")
#'
#' # Several addresses in one call; the `query` column maps rows to inputs
#' pdok_geocode(c("Domplein 1, Utrecht", "Coolsingel 40, Rotterdam"))
#' }
#' @export
pdok_geocode <- function(query, type = NULL, crs = NULL, limit = 1) {
  if (!is.character(query) || length(query) == 0L || anyNA(query) ||
      !all(nzchar(query))) {
    cli::cli_abort("{.arg query} must be a non-empty character vector.")
  }
  check_count(limit, "limit", allow_null = FALSE)
  if (!is.null(crs)) {
    check_crs(crs)
  }
  check_locatieserver_type(type)

  results <- lapply(query, function(q) {
    out <- geocode_free_one(q, type, limit)
    if (nrow(out) > 0L) {
      out$query <- q
    }
    out
  })
  combine_geocode(results, "query", crs)
}

#' Reverse geocode coordinates to the nearest address with the PDOK Locatieserver
#'
#' Finds the address, road or place nearest to each point, through the 'PDOK'
#' Locatieserver reverse service — the inverse of [pdok_geocode()]. Give it `sf`
#' points (in any CRS); it returns the nearest match(es) as an `sf`, including an
#' `afstand` column with the distance in meters.
#'
#' @param points An [sf][sf::st_sf] or `sfc` object of one or more points, in any
#'   CRS. The coordinates are transformed to lon/lat internally for the query.
#' @param type Optional result type to restrict to (see [pdok_geocode()] for the
#'   list); `NULL` (the default) returns the nearest match of any type.
#' @param crs Optional output CRS as an EPSG code (e.g. `28992`). `NULL` keeps
#'   the source CRS (CRS84, lon/lat).
#' @param limit Maximum number of results to return per point (default 1, the
#'   single nearest match).
#'
#' @return An [sf][sf::st_sf] object with one row per match and a `point_id`
#'   column giving the row index of the input point each match came from. The
#'   `afstand` column holds the distance in meters; all other non-geometry
#'   fields the service returns are kept too. Points that match nothing are
#'   dropped (with a warning); a zero-row `sf` is returned when nothing matches
#'   at all.
#' @seealso [pdok_geocode()] for the forward lookup (address to coordinates).
#' @examples
#' \donttest{
#' # A point in the center of Utrecht: the nearest address
#' pt <- sf::st_sfc(sf::st_point(c(5.121, 52.090)), crs = 4326)
#' pdok_reverse_geocode(pt)
#' }
#' @export
pdok_reverse_geocode <- function(points, type = NULL, crs = NULL, limit = 1) {
  if (!inherits(points, c("sf", "sfc"))) {
    cli::cli_abort("{.arg points} must be an {.cls sf} or {.cls sfc} object.")
  }
  geom <- sf::st_geometry(points)
  if (is.na(sf::st_crs(geom))) {
    cli::cli_abort("{.arg points} has no coordinate reference system.")
  }
  if (!all(as.character(sf::st_geometry_type(geom)) == "POINT")) {
    cli::cli_abort("{.arg points} must contain {.val POINT} geometries.")
  }
  check_count(limit, "limit", allow_null = FALSE)
  if (!is.null(crs)) {
    check_crs(crs)
  }
  check_locatieserver_type(type)

  coords <- sf::st_coordinates(sf::st_transform(geom, 4326))
  results <- lapply(seq_len(nrow(coords)), function(i) {
    out <- reverse_one(coords[i, "X"], coords[i, "Y"], type, limit)
    if (nrow(out) > 0L) {
      out$point_id <- i
    }
    out
  })
  combine_geocode(results, "point_id", crs)
}
