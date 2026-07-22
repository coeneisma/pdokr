# Changelog

## pdokr 0.1.0

CRAN release: 2026-07-22

- First release. `pdokr` provides:
  - Dataset and layer discovery with
    [`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md),
    [`pdok_search_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_search_datasets.md),
    [`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md)
    and
    [`pdok_search_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_search_layers.md),
    fetched live from the PDOK index.
  - Loading layers as `sf` objects with
    [`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md),
    with automatic pagination, server-side bounding-box and temporal
    pre-filtering, and client-side CRS transformation. `pdokr` is an OGC
    API Features client and reads vector features only; a dataset that
    serves tiles or coverages instead is reported with a clear error.
  - Spatial filtering by any polygon (or point) with
    [`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md),
    also available in one call through the `filter_by` argument of
    [`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md).
  - Geocoding of addresses and place names with
    [`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md),
    returning `sf` points and administrative polygons. `query` accepts a
    vector, so many locations can be geocoded in one call; a `query`
    column maps each result row back to its input.
  - Reverse geocoding with
    [`pdok_reverse_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_reverse_geocode.md):
    `sf` points to the nearest address, road or place, with the distance
    in meters.
  - The official PDOK basemap as a map background with
    [`pdok_basemap()`](https://coeneisma.github.io/pdokr/reference/pdok_basemap.md),
    returning a raster tile URL (`tmap`/`leaflet`) or a vector style URL
    (`maplibre`/`mapgl`).
