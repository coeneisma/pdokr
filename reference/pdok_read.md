# Read a PDOK layer as an sf object

Loads a layer from PDOK as a simple feature collection over the OGC API
Features service, handling pagination automatically.

## Usage

``` r
pdok_read(
  dataset,
  layer,
  bbox = NULL,
  filter_by = NULL,
  predicate = "intersects",
  datetime = NULL,
  crs = NULL,
  max_features = NULL
)
```

## Arguments

- dataset:

  A dataset id from
  [`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
  (e.g. `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.

- layer:

  A layer id from
  [`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md).

- bbox:

  Optional server-side bounding-box pre-filter: a numeric vector
  `c(xmin, ymin, xmax, ymax)` (assumed CRS84) or an `sf`/`sfc`/`bbox`
  object whose extent is used.

- filter_by:

  Optional `sf`/`sfc` geometry to filter the result by. Its bounding box
  is used as a cheap server-side pre-filter, and the result is then
  filtered exactly with
  [`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md).
  This is the one-call form of the load-then-filter workflow. It is
  usually a polygon (e.g. a municipality), but a point works too:
  filtering an area layer by a point returns the feature that contains
  it (for example the municipality an address falls in).

- predicate:

  Spatial predicate for `filter_by`, passed to
  [`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md)
  (default `"intersects"`).

- datetime:

  Optional temporal filter: a single year (e.g. `2026`, mapped to a
  mid-year instant), an OGC datetime string, or an interval such as
  `"2020-01-01/2025-12-31"`.

- crs:

  Optional output CRS as an EPSG code (e.g. `28992` for RD New). `NULL`
  keeps the source CRS.

- max_features:

  Optional cap on the number of features returned.

## Value

An [sf](https://r-spatial.github.io/sf/reference/sf.html) object with
one row per feature, the layer's attribute columns, and a geometry
column. A zero-row `sf` is returned (with a warning) when nothing
matches.

## Details

By default the data is returned in the coordinate reference system the
service provides (lon/lat, CRS84, for the OGC path). Set `crs` to
receive the data in another CRS; the transformation is done client-side
with
[`sf::st_transform()`](https://r-spatial.github.io/sf/reference/st_transform.html).

## See also

[`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md)
to find layer ids.

## Examples

``` r
# \donttest{
# A whole layer: the Dutch national parks
parks <- pdok_read("rvo/nationale-parken-geharmoniseerd", "protectedsite")

# Municipalities for 2024, in RD New (EPSG:28992)
pdok_read(
  "cbs/gebiedsindelingen", "gemeente_gegeneraliseerd",
  datetime = 2024, crs = 28992, max_features = 5
)
#> Simple feature collection with 5 features and 8 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 136985.7 ymin: 473841.6 xmax: 269937.9 ymax: 592658.9
#> Projected CRS: Amersfoort / RD New
#> # A tibble: 5 × 9
#>   einddatum              id jaarcode jrstatcode rubriek  startdatum         
#> * <dttm>              <int>    <int> <chr>      <chr>    <dttm>             
#> 1 2024-12-31 23:59:59     1     2024 2024GM0014 gemeente 2024-01-01 00:00:00
#> 2 2024-12-31 23:59:59     2     2024 2024GM0034 gemeente 2024-01-01 00:00:00
#> 3 2024-12-31 23:59:59     3     2024 2024GM0037 gemeente 2024-01-01 00:00:00
#> 4 2024-12-31 23:59:59     4     2024 2024GM0047 gemeente 2024-01-01 00:00:00
#> 5 2024-12-31 23:59:59     5     2024 2024GM0050 gemeente 2024-01-01 00:00:00
#> # ℹ 3 more variables: statcode <chr>, statnaam <chr>,
#> #   geometry <MULTIPOLYGON [m]>

# One-call area filter: national parks within the province of Utrecht
provinces <- pdok_read(
  "cbs/gebiedsindelingen", "provincie_gegeneraliseerd", datetime = 2024
)
utrecht <- provinces[provinces$statnaam == "Utrecht", ]
parks_utrecht <- pdok_read(
  "rvo/nationale-parken-geharmoniseerd", "protectedsite",
  filter_by = utrecht
)
# }
```
