# AHN elevation rasters from PDOK, returned as a terra SpatRaster.
#
# This is pdokr's first raster capability. PDOK serves AHN through a classic OGC
# Web Coverage Service (WCS), not an OGC API. A general `pdok_read_coverage()`
# for arbitrary PDOK WCS coverages (aerial imagery, land cover, ...) may be added
# later; for now pdokr covers only AHN height data.

ahn_wcs_url <- "https://service.pdok.nl/rws/actueel-hoogtebestand-nederland/wcs/v1_0"
ahn_coverages <- c(dtm = "dtm_05m", dsm = "dsm_05m")
ahn_resolution <- 0.5
# The WCS rejects very large requests; ~4000x4000 cells is verified to work.
ahn_max_cells <- 4000 * 4000

#' Bounding box of `area` in RD New (EPSG:28992)
#' @noRd
ahn_bbox_rd <- function(area, call = rlang::caller_env()) {
  geom <- if (inherits(area, "bbox")) {
    sf::st_as_sfc(area)
  } else if (inherits(area, c("sf", "sfc"))) {
    sf::st_geometry(area)
  } else {
    cli::cli_abort(
      "{.arg area} must be an {.cls sf}, {.cls sfc}, or {.cls bbox} object.",
      call = call
    )
  }
  if (is.na(sf::st_crs(geom))) {
    cli::cli_abort("{.arg area} has no CRS; set one so it can be located.", call = call)
  }
  sf::st_bbox(sf::st_transform(geom, 28992))
}

#' Read AHN elevation for an area as a raster
#'
#' Downloads the 'Actueel Hoogtebestand Nederland' (AHN) height data for the
#' extent of `area` and returns it as a `terra` `SpatRaster`. Unlike pdokr's
#' vector functions, which return `sf`, this returns **raster** data: a grid of
#' height values (metres relative to NAP) at 0.5 m resolution.
#'
#' @param area An `sf`, `sfc`, or `bbox` object; its bounding box defines the
#'   area to fetch. Any CRS is accepted and converted to RD New for the request.
#' @param model Which elevation model: `"dtm"` (digital terrain model — bare
#'   ground) or `"dsm"` (digital surface model — including buildings and
#'   vegetation). The difference `dsm - dtm` gives object heights.
#' @param crs Optional output CRS as an EPSG code to reproject to. `NULL` (the
#'   default) keeps the native RD New (EPSG:28992).
#'
#' @return A `terra` [SpatRaster][terra::rast] of heights in metres (NAP).
#'
#' @details
#' AHN is served through a classic OGC **Web Coverage Service** (WCS), not an OGC
#' API. The bounding box requests a subset; the service limits the request size,
#' so areas larger than about 2 x 2 km (at 0.5 m) are rejected — read a smaller
#' area. Requires the `terra` package.
#'
#' @examples
#' \donttest{
#' # Terrain around the Utrecht Dom, and the surface (incl. buildings)
#' centre <- sf::st_buffer(pdok_geocode("Domplein, Utrecht", crs = 28992), 300)
#' dtm <- pdok_ahn(centre, "dtm")
#' dsm <- pdok_ahn(centre, "dsm")
#' object_height <- dsm - dtm
#' }
#' @seealso [pdok_read()] for vector data as `sf`.
#' @export
pdok_ahn <- function(area, model = c("dtm", "dsm"), crs = NULL) {
  model <- match.arg(model)
  if (!requireNamespace("terra", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.pkg terra} package is required for {.fn pdok_ahn}.",
      "i" = "Install it with {.code install.packages(\"terra\")}."
    ))
  }

  bbox <- ahn_bbox_rd(area)
  cells <- ceiling((bbox[["xmax"]] - bbox[["xmin"]]) / ahn_resolution) *
    ceiling((bbox[["ymax"]] - bbox[["ymin"]]) / ahn_resolution)
  if (cells > ahn_max_cells) {
    cli::cli_abort(c(
      "The requested area is too large for the AHN service \\
       ({round(cells / 1e6, 1)} million cells at {ahn_resolution} m).",
      "i" = "Read a smaller area (up to about 2 x 2 km)."
    ))
  }

  req <- httr2::req_url_query(
    pdok_request(ahn_wcs_url),
    service = "WCS", version = "2.0.1", request = "GetCoverage",
    coverageId = ahn_coverages[[model]], format = "image/tiff",
    subset = c(
      sprintf("x(%.3f,%.3f)", bbox[["xmin"]], bbox[["xmax"]]),
      sprintf("y(%.3f,%.3f)", bbox[["ymin"]], bbox[["ymax"]])
    ),
    .multi = "explode"
  )
  resp <- pdok_perform(req)

  tmp <- tempfile(fileext = ".tif")
  writeBin(httr2::resp_body_raw(resp), tmp)
  out <- terra::rast(tmp)
  names(out) <- model
  if (!is.null(crs)) {
    out <- terra::project(out, paste0("EPSG:", crs))
  }
  out
}
