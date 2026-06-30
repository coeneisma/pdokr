# Reference basemaps from PDOK, returned as a URL for use with any mapping
# package. No data is fetched; the function only builds the right URL, so it
# works offline and instantly.

# Internal: raster WMTS tile-URL templates (EPSG:3857, {z}/{x}/{y}).
pdok_basemap_raster <- c(
  standaard = "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/standaard/EPSG:3857/{z}/{x}/{y}.png",
  grijs     = "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png",
  pastel    = "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/pastel/EPSG:3857/{z}/{x}/{y}.png",
  water     = "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/water/EPSG:3857/{z}/{x}/{y}.png",
  luchtfoto = "https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg"
)

# Internal: OGC API Maps (Mapbox GL) style ids, WebMercatorQuad.
pdok_basemap_vector <- c(
  standaard     = "standaard__webmercatorquad",
  zonder_labels = "standaard_zonder_labels__webmercatorquad",
  luchtfoto     = "luchtfoto_labels__webmercatorquad",
  darkmode      = "darkmode__webmercatorquad"
)

#' A PDOK basemap to use as a map background
#'
#' Returns the URL of the official PDOK 'BRT Achtergrondkaart' (or aerial
#' imagery) for use as the background of a map. Nothing is downloaded — the
#' function only constructs the URL, so it works offline and instantly. Hand the
#' result to any mapping package: `tmap` and `leaflet` take the raster tile URL,
#' `maplibre`/`mapgl` take the vector style URL.
#'
#' @param style The basemap style. For `format = "raster"`: one of
#'   `"standaard"`, `"grijs"`, `"pastel"`, `"water"`, or `"luchtfoto"` (aerial
#'   imagery). For `format = "vector"`: one of `"standaard"`, `"zonder_labels"`,
#'   `"luchtfoto"`, or `"darkmode"`.
#' @param format `"raster"` (the default) returns a WMTS tile-URL template
#'   (`{z}/{x}/{y}`, in Web Mercator / EPSG:3857) that works with `tmap`,
#'   `leaflet` and `maplibre`/`mapgl`. `"vector"` returns a Mapbox GL style URL
#'   for `maplibre`/`mapgl`.
#'
#' @return A single string: a raster tile-URL template, or a vector style URL.
#'
#' @section Attribution:
#' The map data is © Kadaster / PDOK. Show this attribution on any map that uses
#' the basemap.
#'
#' @examples
#' # Raster tile URL (tmap / leaflet)
#' pdok_basemap()
#' pdok_basemap("grijs")
#'
#' # Vector style URL (maplibre / mapgl)
#' pdok_basemap("standaard", format = "vector")
#' @export
pdok_basemap <- function(style = "standaard", format = c("raster", "vector")) {
  format <- match.arg(format)
  if (!rlang::is_string(style)) {
    cli::cli_abort("{.arg style} must be a single string.")
  }

  lookup <- if (format == "raster") pdok_basemap_raster else pdok_basemap_vector
  if (!style %in% names(lookup)) {
    cli::cli_abort(c(
      "{.val {style}} is not a valid {format} basemap style.",
      "i" = "Valid {format} styles: {.or {.val {names(lookup)}}}."
    ))
  }

  if (format == "raster") {
    unname(lookup[[style]])
  } else {
    paste0(
      "https://api.pdok.nl/kadaster/brt-achtergrondkaart/ogc/v1/styles/",
      lookup[[style]], "?f=mapbox"
    )
  }
}
