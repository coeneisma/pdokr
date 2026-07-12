# Reverse geocode coordinates to the nearest address with the PDOK Locatieserver

Finds the address, road or place nearest to each point, through the
'PDOK' Locatieserver reverse service — the inverse of
[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md).
Give it `sf` points (in any CRS); it returns the nearest match(es) as an
`sf`, including an `afstand` column with the distance in meters.

## Usage

``` r
pdok_reverse_geocode(points, type = NULL, crs = NULL, limit = 1)
```

## Arguments

- points:

  An [sf](https://r-spatial.github.io/sf/reference/sf.html) or `sfc`
  object of one or more points, in any CRS. The coordinates are
  transformed to lon/lat internally for the query.

- type:

  Optional result type to restrict to (see
  [`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
  for the list); `NULL` (the default) returns the nearest match of any
  type.

- crs:

  Optional output CRS as an EPSG code (e.g. `28992`). `NULL` keeps the
  source CRS (CRS84, lon/lat).

- limit:

  Maximum number of results to return per point (default 1, the single
  nearest match).

## Value

An [sf](https://r-spatial.github.io/sf/reference/sf.html) object with
one row per match and a `point_id` column giving the row index of the
input point each match came from. The `afstand` column holds the
distance in meters; all other non-geometry fields the service returns
are kept too. Points that match nothing are dropped (with a warning); a
zero-row `sf` is returned when nothing matches at all.

## See also

[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
for the forward lookup (address to coordinates).

## Examples

``` r
# \donttest{
# A point in the center of Utrecht: the nearest address
pt <- sf::st_sfc(sf::st_point(c(5.121, 52.090)), crs = 4326)
pdok_reverse_geocode(pt)
#> Simple feature collection with 1 feature and 37 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 5.120999 ymin: 52.09001 xmax: 5.120999 ymax: 52.09001
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 38
#>   point_id weergavenaam  type  afstand gemeentenaam woonplaatsnaam provincienaam
#>      <int> <chr>         <chr>   <dbl> <chr>        <chr>          <chr>        
#> 1        1 Donkeregaard… adres    0.68 Utrecht      Utrecht        Utrecht      
#> # ℹ 31 more variables: bron <chr>, woonplaatscode <chr>, wijkcode <chr>,
#> #   huis_nlt <chr>, openbareruimtetype <chr>, buurtnaam <chr>,
#> #   gemeentecode <chr>, rdf_seealso <chr>, suggest <chr>, adrestype <chr>,
#> #   straatnaam_verkort <chr>, id <chr>, gekoppeld_perceel <chr>,
#> #   buurtcode <chr>, wijknaam <chr>, identificatie <chr>,
#> #   openbareruimte_id <chr>, waterschapsnaam <chr>, provinciecode <chr>,
#> #   postcode <chr>, nummeraanduiding_id <chr>, waterschapscode <chr>, …
# }
```
