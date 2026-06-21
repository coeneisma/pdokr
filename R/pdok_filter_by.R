# Internal: map a predicate name to its sf spatial-predicate function.
filter_predicate <- function(predicate, call = rlang::caller_env()) {
  predicates <- c(
    "intersects", "within", "contains", "overlaps", "touches",
    "crosses", "covers", "covered_by", "disjoint"
  )
  if (!rlang::is_string(predicate) || !predicate %in% predicates) {
    cli::cli_abort(
      c(
        "{.arg predicate} must be one of {.or {.val {predicates}}}.",
        "x" = "You supplied {.val {predicate}}."
      ),
      call = call
    )
  }
  getExportedValue("sf", paste0("st_", predicate))
}

#' Spatially filter an sf layer by any polygon
#'
#' Keeps the features of `data` that relate to `filter_geometry` under a spatial
#' predicate. This is a thin, convenient wrapper around [sf::st_filter()] that
#' also reconciles coordinate reference systems for you: `filter_geometry` is
#' transformed to the CRS of `data` before filtering.
#'
#' `filter_geometry` can be *any* polygon: a municipality from
#' [pdok_read()] on the CBS administrative boundaries, a nature reserve, a
#' water-authority area, a hand-drawn polygon, or another PDOK layer.
#'
#' The plain-`sf` equivalent is `data[filter_geometry, , op = sf::st_intersects]`
#' (after matching CRS); use that if you prefer to drop down to `sf`.
#'
#' @param data An [sf][sf::st_sf] object to filter (for example a layer loaded
#'   with [pdok_read()]).
#' @param filter_geometry An `sf` or `sfc` object whose geometry defines the
#'   area of interest.
#' @param predicate The spatial relationship to test, one of `"intersects"`,
#'   `"within"`, `"contains"`, `"overlaps"`, `"touches"`, `"crosses"`,
#'   `"covers"`, `"covered_by"`, or `"disjoint"`.
#'
#' @return An [sf][sf::st_sf] object: the subset of `data` whose features satisfy
#'   `predicate` with respect to `filter_geometry`.
#' @seealso [pdok_read()], whose `filter_by` argument applies this filter while
#'   loading.
#' @examples
#' \donttest{
#' # All national parks that intersect the province of Utrecht
#' utrecht <- pdok_read(
#'   "cbs/gebiedsindelingen", "provincie_gegeneraliseerd",
#'   datetime = 2024
#' )
#' utrecht <- utrecht[utrecht$statnaam == "Utrecht", ]
#' parks <- pdok_read("rvo/nationale-parken-geharmoniseerd", "protectedsite")
#' pdok_filter_by(parks, utrecht)
#' }
#' @export
pdok_filter_by <- function(data, filter_geometry, predicate = "intersects") {
  if (!inherits(data, "sf")) {
    cli::cli_abort("{.arg data} must be an {.cls sf} object.")
  }
  if (!inherits(filter_geometry, c("sf", "sfc"))) {
    cli::cli_abort("{.arg filter_geometry} must be an {.cls sf} or {.cls sfc} object.")
  }
  if (is.na(sf::st_crs(data))) {
    cli::cli_abort("{.arg data} has no coordinate reference system.")
  }
  if (is.na(sf::st_crs(filter_geometry))) {
    cli::cli_abort("{.arg filter_geometry} has no coordinate reference system.")
  }

  op <- filter_predicate(predicate)
  geom <- sf::st_transform(sf::st_geometry(filter_geometry), sf::st_crs(data))
  sf::st_filter(data, geom, .predicate = op)
}
