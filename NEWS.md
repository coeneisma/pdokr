# pdokr (development version)

* First release. `pdokr` provides:
  * Dataset and layer discovery with `pdok_list_datasets()`,
    `pdok_search_datasets()`, `pdok_list_layers()` and `pdok_search_layers()`,
    fetched live from the PDOK index.
  * Loading layers as `sf` objects with `pdok_read()`, with automatic
    pagination, server-side bounding-box and temporal pre-filtering, and
    client-side CRS transformation.
  * Spatial filtering by any polygon (or point) with `pdok_filter_by()`, also
    available in one call through the `filter_by` argument of `pdok_read()`.
  * Geocoding of addresses and place names with `pdok_geocode()`, returning
    `sf` points and administrative polygons.
  * The official PDOK basemap as a map background with `pdok_basemap()`,
    returning a raster tile URL (`tmap`/`leaflet`) or a vector style URL
    (`maplibre`/`mapgl`).
  * AHN (Actueel Hoogtebestand Nederland) elevation data with `pdok_ahn()`,
    returning a `terra` raster of terrain (`dtm`) or surface (`dsm`) heights —
    pdokr's first raster capability, alongside the vector `sf` functions.
