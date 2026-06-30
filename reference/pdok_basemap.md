# A PDOK basemap to use as a map background

Returns the URL of the official PDOK 'BRT Achtergrondkaart' (or aerial
imagery) for use as the background of a map. Nothing is downloaded — the
function only constructs the URL, so it works offline and instantly.
Hand the result to any mapping package: `tmap` and `leaflet` take the
raster tile URL, `maplibre`/`mapgl` take the vector style URL.

## Usage

``` r
pdok_basemap(style = "standaard", format = c("raster", "vector"))
```

## Arguments

- style:

  The basemap style. For `format = "raster"`: one of `"standaard"`,
  `"grijs"`, `"pastel"`, `"water"`, or `"luchtfoto"` (aerial imagery).
  For `format = "vector"`: one of `"standaard"`, `"zonder_labels"`,
  `"luchtfoto"`, or `"darkmode"`.

- format:

  `"raster"` (the default) returns a WMTS tile-URL template
  (`{z}/{x}/{y}`, in Web Mercator / EPSG:3857) that works with `tmap`,
  `leaflet` and `maplibre`/`mapgl`. `"vector"` returns a Mapbox GL style
  URL for `maplibre`/`mapgl`.

## Value

A single string: a raster tile-URL template, or a vector style URL.

## Attribution

The map data is © Kadaster / PDOK. Show this attribution on any map that
uses the basemap.

## Examples

``` r
# Raster tile URL (tmap / leaflet)
pdok_basemap()
#> [1] "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/standaard/EPSG:3857/{z}/{x}/{y}.png"
pdok_basemap("grijs")
#> [1] "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png"

# Vector style URL (maplibre / mapgl)
pdok_basemap("standaard", format = "vector")
#> [1] "https://api.pdok.nl/kadaster/brt-achtergrondkaart/ogc/v1/styles/standaard__webmercatorquad?f=mapbox"
```
