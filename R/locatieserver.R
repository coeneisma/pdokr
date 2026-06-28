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

  pull <- function(key) {
    if (identical(key, "score")) {
      return(vapply(docs, function(d) as.numeric(d$score %||% NA), numeric(1)))
    }
    vapply(docs, function(d) {
      v <- d[[key]]
      if (is.null(v)) NA_character_ else paste(as.character(v), collapse = "; ")
    }, character(1))
  }

  attrs <- tibble::as_tibble(stats::setNames(lapply(keys, pull), keys))

  # Surface the most useful fields first; keep the rest in their original order.
  preferred <- intersect(
    c("weergavenaam", "type", "score", "gemeentenaam", "woonplaatsnaam",
      "provincienaam"),
    keys
  )
  attrs <- attrs[, c(preferred, setdiff(keys, preferred)), drop = FALSE]

  sf::st_sf(attrs, geometry = geometry)
}

#' Geocode an address or place name with the PDOK Locatieserver
#'
#' Looks up addresses, place names, postcodes, municipalities, provinces and
#' more through the 'PDOK' Locatieserver, returning the results as a simple
#' feature collection. Point geometry is returned for addresses and places, and
#' boundary polygons for administrative areas such as municipalities — so a
#' result drops straight into the `filter_by` argument of [pdok_read()].
#'
#' @param query A single non-empty search string, e.g.
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
#' @param limit Maximum number of results to return (default 1).
#'
#' @return An [sf][sf::st_sf] object with one row per match. All non-geometry
#'   fields the service returns are kept as columns (with `weergavenaam`,
#'   `type`, `score`, and the administrative names first); the geometry is a
#'   point for addresses and places and a polygon for administrative areas. A
#'   zero-row `sf` is returned (with a warning) when nothing matches.
#' @seealso [pdok_read()], whose `filter_by` argument accepts the result.
#' @examples
#' \donttest{
#' # An address: a point
#' pdok_geocode("Park Arenberg 88, De Bilt")
#'
#' # A municipality: a boundary polygon
#' pdok_geocode("De Bilt", type = "gemeente")
#' }
#' @export
pdok_geocode <- function(query, type = NULL, crs = NULL, limit = 1) {
  if (!rlang::is_string(query) || !nzchar(query)) {
    cli::cli_abort("{.arg query} must be a single non-empty string.")
  }
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) ||
      limit < 1 || limit != round(limit)) {
    cli::cli_abort("{.arg limit} must be a single positive whole number.")
  }

  if (!is.null(type) &&
      (!rlang::is_string(type) || !type %in% locatieserver_types)) {
    cli::cli_abort(c(
      "{.arg type} must be one of {.or {.val {locatieserver_types}}}.",
      "x" = "You supplied {.val {type}}."
    ))
  }

  q <- list(q = query, rows = limit, fl = "*,score")
  if (!is.null(type)) {
    q$fq <- paste0("type:", type)
  }

  resp <- pdok_perform(
    pdok_request(paste0(pdok_base_urls$locatieserver, "/free"), query = q)
  )
  docs <- httr2::resp_body_json(resp)$response$docs
  out <- parse_locatieserver(docs)

  if (nrow(out) == 0L) {
    cli::cli_warn(c(
      "No results for query {.val {query}}.",
      "i" = "Check the spelling, or relax the {.arg type} filter."
    ))
    return(out)
  }

  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  out
}
