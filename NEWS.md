# pdokr (development version)

* Support for server-side attribute filtering with CQL2, which
  PDOK offers on every dataset with OGC API Features (each layer exposes a
  selected set of filterable fields):
  * `pdok_read()` gains a `filter` argument: a `pdok_where()` expression or a
    raw CQL2 text string, executed by the server so only matching features are
    downloaded. It combines with `bbox`/`filter_by` (conditions are combined with AND).
  * `pdok_where()` translates R syntax (`==`, `%in%`, `&`, `has()`, `like()`,
    `casei()`, ...) to CQL2. A `%in%` over more than 300 values is split over
    multiple requests automatically (with a progress bar), so filtering on
    thousands of ids works out of the box; `has()` matches one value inside multi-value fields such
    as the BAG `gebruiksdoel`.
  * `pdok_list_queryables()` lists the fields a filter can use for a layer,
    and `pdok_list_layers()` gains a `queryables = TRUE` option that adds
    them as a column for every layer of a dataset.
* `pdok_read()` with a small set of points as `filter_by` (up to 200, within
  roughly 20 km) now also asks the server for only the features touching
  those points, via a spatial CQL2 filter. "Which building/municipality does
  each of these addresses fall in" thus downloads those features instead of
  everything in the points' bounding box. The exact client-side clip and the
  `predicate` semantics are unchanged.
* New `pdok_read_href()` follows the feature links that some layers carry
  (such as `pand.href` on a BAG `verblijfsobject`). It reads each distinct
  linked feature once, with bounded concurrency and a rate limit, and
  attaches it to the rows that link to it, like a join that also brings the
  linked geometry along. `keep = FALSE` returns just the linked features.
  This is the efficient way to get, for example, the buildings behind a list
  of addresses.
* HTTP error messages now include the server's own explanation when the
  response provides one (e.g. CQL2 parse errors). A filter on a field that is
  not queryable additionally points to `pdok_list_queryables()`.

# pdokr 0.1.0

* First release. `pdokr` provides:
  * Dataset and layer discovery with `pdok_list_datasets()`,
    `pdok_search_datasets()`, `pdok_list_layers()` and `pdok_search_layers()`,
    fetched live from the PDOK index.
  * Loading layers as `sf` objects with `pdok_read()`, with automatic
    pagination, server-side bounding-box and temporal pre-filtering, and
    client-side CRS transformation. `pdokr` is an OGC API Features client and
    reads vector features only; a dataset that serves tiles or coverages
    instead is reported with a clear error.
  * Spatial filtering by any polygon (or point) with `pdok_filter_by()`, also
    available in one call through the `filter_by` argument of `pdok_read()`.
  * Geocoding of addresses and place names with `pdok_geocode()`, returning
    `sf` points and administrative polygons. `query` accepts a vector, so many
    locations can be geocoded in one call; a `query` column maps each result row
    back to its input.
  * Reverse geocoding with `pdok_reverse_geocode()`: `sf` points to the nearest
    address, road or place, with the distance in meters.
  * The official PDOK basemap as a map background with `pdok_basemap()`,
    returning a raster tile URL (`tmap`/`leaflet`) or a vector style URL
    (`maplibre`/`mapgl`).
