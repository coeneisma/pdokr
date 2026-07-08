#' @details
#' `pdokr` is a client for PDOK's **OGC API Features** services. It reads
#' *vector* feature data — points, lines, and polygons — and returns it as
#' [sf][sf::st_sf] objects. Raster, tile, and coverage services (such as
#' elevation grids or map-tile backgrounds) are out of scope: `pdok_read()`
#' loads features only. A handful of datasets listed by
#' [pdok_list_datasets()] serve tiles or coverages rather than features;
#' those cannot be read as `sf`, and `pdok_read()` reports this clearly. For
#' the official PDOK map background, use [pdok_basemap()].
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL
