# Geocode addresses or place names with the PDOK Locatieserver

Looks up addresses, place names, postcodes, municipalities, provinces
and more through the 'PDOK' Locatieserver, returning the results as a
simple feature collection. Point geometry is returned for addresses and
places, and boundary polygons for administrative areas such as
municipalities — so a result drops straight into the `filter_by`
argument of
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md).

## Usage

``` r
pdok_geocode(query, type = NULL, crs = NULL, limit = 1)
```

## Arguments

- query:

  A character vector of one or more non-empty search strings, e.g.
  `"Park Arenberg 88, De Bilt"`.

- type:

  Optional result type to restrict to, one of `"adres"`, `"postcode"`,
  `"weg"`, `"woonplaats"`, `"gemeente"`, `"provincie"`, `"buurt"`,
  `"wijk"`, `"perceel"`, `"hectometerpaal"`, or `"appartementsrecht"`.
  `NULL` (the default) returns the best matches of any type, ranked by
  the service's relevance `score`. Use `type` to disambiguate names that
  exist in several categories (for example `"Utrecht"` is both a
  municipality and a province).

- crs:

  Optional output CRS as an EPSG code (e.g. `28992`). `NULL` keeps the
  source CRS (CRS84, lon/lat).

- limit:

  Maximum number of results to return per query (default 1).

## Value

An [sf](https://r-spatial.github.io/sf/reference/sf.html) object with
one row per match and a `query` column identifying the input each row
came from. All non-geometry fields the service returns are kept as
columns (with `query`, `weergavenaam`, `type`, `score`, and the
administrative names first); the geometry is a point for addresses and
places and a polygon for administrative areas. Queries that match
nothing are dropped (with a warning), so the result can have fewer rows
than `query` has elements; a zero-row `sf` is returned when nothing
matches at all.

## Details

`query` may be a vector, geocoding many locations in one call (for
example a column of addresses). Each result row carries a `query` column
with the input it came from, so the output maps back to the input even
when a query returns several candidates or none.

## See also

[`pdok_reverse_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_reverse_geocode.md)
for the reverse lookup (coordinates to the nearest address), and
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md),
whose `filter_by` argument accepts the result.

## Examples

``` r
# \donttest{
# An address: a point
pdok_geocode("Park Arenberg 88, De Bilt")
#> Simple feature collection with 1 feature and 37 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 5.171466 ymin: 52.10607 xmax: 5.171466 ymax: 52.10607
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 38
#>   query weergavenaam type  score gemeentenaam woonplaatsnaam provincienaam bron 
#>   <chr> <chr>        <chr> <dbl> <chr>        <chr>          <chr>         <chr>
#> 1 Park… Park Arenbe… adres  24.8 De Bilt      De Bilt        Utrecht       BAG  
#> # ℹ 30 more variables: woonplaatscode <chr>, wijkcode <chr>, huis_nlt <chr>,
#> #   openbareruimtetype <chr>, buurtnaam <chr>, gemeentecode <chr>,
#> #   rdf_seealso <chr>, suggest <chr>, adrestype <chr>,
#> #   straatnaam_verkort <chr>, id <chr>, gekoppeld_perceel <chr>,
#> #   buurtcode <chr>, wijknaam <chr>, identificatie <chr>,
#> #   openbareruimte_id <chr>, waterschapsnaam <chr>, provinciecode <chr>,
#> #   postcode <chr>, nummeraanduiding_id <chr>, waterschapscode <chr>, …

# A municipality: a boundary polygon
pdok_geocode("De Bilt", type = "gemeente")
#> Simple feature collection with 1 feature and 16 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 5.09489 ymin: 52.0849 xmax: 5.23093 ymax: 52.20427
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 17
#>   query  weergavenaam type  score gemeentenaam provincienaam bron  identificatie
#>   <chr>  <chr>        <chr> <dbl> <chr>        <chr>         <chr> <chr>        
#> 1 De Bi… Gemeente De… geme…  13.4 De Bilt      Utrecht       Best… 0310         
#> # ℹ 9 more variables: provinciecode <chr>, gemeentecode <chr>, suggest <chr>,
#> #   provincieafkorting <chr>, id <chr>, shards <chr>, typesortering <chr>,
#> #   shard <chr>, geometry <MULTIPOLYGON [°]>

# Several addresses in one call; the `query` column maps rows to inputs
pdok_geocode(c("Domplein 1, Utrecht", "Coolsingel 40, Rotterdam"))
#> Simple feature collection with 2 features and 38 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 4.479201 ymin: 51.92272 xmax: 5.1224 ymax: 52.09118
#> Geodetic CRS:  WGS 84
#> # A tibble: 2 × 39
#>   query weergavenaam type  score gemeentenaam woonplaatsnaam provincienaam bron 
#>   <chr> <chr>        <chr> <dbl> <chr>        <chr>          <chr>         <chr>
#> 1 Domp… Domplein, U… weg    15.8 Utrecht      Utrecht        Utrecht       BAG/…
#> 2 Cool… Coolsingel … adres  14.8 Rotterdam    Rotterdam      Zuid-Holland  BAG  
#> # ℹ 31 more variables: woonplaatscode <chr>, nwb_id <chr>,
#> #   openbareruimtetype <chr>, gemeentecode <chr>, rdf_seealso <chr>,
#> #   suggest <chr>, straatnaam_verkort <chr>, id <chr>, identificatie <chr>,
#> #   openbareruimte_id <chr>, provinciecode <chr>, provincieafkorting <chr>,
#> #   straatnaam <chr>, shards <chr>, typesortering <chr>, shard <chr>,
#> #   wijkcode <chr>, huis_nlt <chr>, buurtnaam <chr>, adrestype <chr>,
#> #   gekoppeld_perceel <chr>, buurtcode <chr>, wijknaam <chr>, …
# }
```
