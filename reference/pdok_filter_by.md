# Spatially filter an sf layer by any polygon

Keeps the features of `data` that relate to `filter_geometry` under a
spatial predicate. It does what
[`sf::st_filter()`](https://r-spatial.github.io/sf/reference/st_join.html)
does, and additionally reconciles coordinate reference systems for you:
`filter_geometry` is transformed to the CRS of `data` before filtering.

## Usage

``` r
pdok_filter_by(data, filter_geometry, predicate = "intersects")
```

## Arguments

- data:

  An [sf](https://r-spatial.github.io/sf/reference/sf.html) object to
  filter (for example a layer loaded with
  [`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)).

- filter_geometry:

  An `sf` or `sfc` object whose geometry defines the area of interest.

- predicate:

  The spatial relationship to test, one of `"intersects"`, `"within"`,
  `"contains"`, `"overlaps"`, `"touches"`, `"crosses"`, `"covers"`,
  `"covered_by"`, or `"disjoint"`.

## Value

An [sf](https://r-spatial.github.io/sf/reference/sf.html) object: the
subset of `data` whose features satisfy `predicate` with respect to
`filter_geometry`.

## Details

`filter_geometry` can be *any* polygon: a municipality from
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)
on the CBS administrative boundaries, a nature reserve, a
water-authority area, a hand-drawn polygon, or another PDOK layer.

The plain-`sf` equivalent is
`data[filter_geometry, , op = sf::st_intersects]` (after matching CRS);
use that if you prefer to drop down to `sf`.

## See also

[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md),
whose `filter_by` argument applies this filter while loading.

## Examples

``` r
# \donttest{
# All national parks that intersect the province of Utrecht
utrecht <- pdok_read(
  "cbs/gebiedsindelingen", "provincie_gegeneraliseerd",
  datetime = 2024
)
utrecht <- utrecht[utrecht$statnaam == "Utrecht", ]
parks <- pdok_read("rvo/nationale-parken-geharmoniseerd", "protectedsite")
#> ⠙ Downloading PDOK features: 22 fetched
pdok_filter_by(parks, utrecht)
#> Simple feature collection with 1 feature and 14 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 5.147185 ymin: 51.95757 xmax: 5.566058 ymax: 52.22923
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 15
#>   id          gml_id language legalfoundationdate legalfoundationdocum…¹ localid
#>   <chr>       <chr>  <chr>    <chr>               <chr>                  <chr>  
#> 1 4d5b664b-7… G_4a2… nld      20131001            prov. Utrecht          L_4a24…
#> # ℹ abbreviated name: ¹​legalfoundationdocument
#> # ℹ 9 more variables: namespace <chr>, namestatus <chr>, nativeness <chr>,
#> #   pronunciation <chr>, script <chr>, siteprotectionclassification <chr>,
#> #   sourceofname <chr>, text <chr>, geometry <MULTIPOLYGON [°]>
# }
```
