# Geocoding: from names to locations

[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
turns a name — an address, a postcode, a street, a town, a municipality,
a province — into spatial data, using the PDOK
[Locatieserver](https://www.pdok.nl/). The result is an `sf` object, so
it plugs straight into the rest of `pdokr`: most usefully, a geocoded
boundary can be handed to the `filter_by` argument of
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md).

``` r

library(pdokr)
library(tmap)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
```

## A name to a point

In its simplest form you pass a query and get back the single best
match.

``` r

home <- pdok_geocode("Domplein 1, Utrecht")
home |> select(weergavenaam, type, score)
#> Simple feature collection with 1 feature and 3 fields
#> Geometry type: MULTILINESTRING
#> Dimension:     XY
#> Bounding box:  xmin: 5.12111 ymin: 52.09004 xmax: 5.1224 ymax: 52.09118
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 4
#>   weergavenaam      type  score                                         geometry
#>   <chr>             <chr> <dbl>                            <MULTILINESTRING [°]>
#> 1 Domplein, Utrecht weg    15.8 ((5.12193 52.09004, 5.12149 52.09093), (5.12149…
```

It is an ordinary `sf` object with a point geometry, ready to map.

``` r

tmap_mode("view")
#> ℹ tmap modes "plot" - "view"
#> ℹ toggle with `tmap::ttm()`

tm_basemap(pdok_basemap("grijs")) +
  tm_shape(home) +
  tm_dots(fill = "#E8631C", size = 1) +
  tm_credits("Kaartgegevens © Kadaster")
```

## Search levels: the `type` argument

The Locatieserver does not only know addresses. Every result has a
`type`, and the geometry you get back depends on it — a point for
pinpoint locations, a line for a road, a polygon for an area.

| `type`              | Geometry | What it is                 |
|---------------------|----------|----------------------------|
| `adres`             | point    | a specific address         |
| `postcode`          | point    | the center of a postcode   |
| `hectometerpaal`    | point    | a motorway distance marker |
| `appartementsrecht` | point    | an apartment right         |
| `weg`               | line     | a (named) road             |
| `buurt`, `wijk`     | polygon  | a neighborhood or district |
| `woonplaats`        | polygon  | a town or city             |
| `gemeente`          | polygon  | a municipality             |
| `provincie`         | polygon  | a province                 |
| `perceel`           | polygon  | a cadastral parcel         |

By default
[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
returns the best match of *any* type, ranked by the service’s relevance
`score`. That is convenient, but a single name often exists at several
levels — “Utrecht” is a municipality, a province, *and* a town:

``` r

pdok_geocode("Utrecht", limit = 5) |>
  select(weergavenaam, type, score)
#> Simple feature collection with 5 features and 3 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 4.9701 ymin: 52.02628 xmax: 5.19515 ymax: 52.14205
#> Geodetic CRS:  WGS 84
#> # A tibble: 5 × 4
#>   weergavenaam                  type       score                        geometry
#>   <chr>                         <chr>      <dbl>              <MULTIPOLYGON [°]>
#> 1 Gemeente Utrecht              gemeente   10.2  (((5.01801 52.06222, 5.01707 5…
#> 2 Utrecht, Utrecht, Utrecht     woonplaats  9.24 (((5.01514 52.11395, 5.01553 5…
#> 3 Haarzuilens, Utrecht, Utrecht woonplaats  9.02 (((4.97775 52.13057, 4.97394 5…
#> 4 Vleuten, Utrecht, Utrecht     woonplaats  9.02 (((4.98085 52.10015, 4.98933 5…
#> 5 De Meern, Utrecht, Utrecht    woonplaats  8.95 (((5.0429 52.08946, 5.04283 52…
```

Pass `type` to pin down exactly which level you mean. The same query
then returns very different geometry:

``` r

point <- pdok_geocode("Domplein 1, Utrecht")          # adres  -> point
road  <- pdok_geocode("Oudegracht, Utrecht", type = "weg")   # weg    -> line
area  <- pdok_geocode("Binnenstad, Utrecht", type = "wijk")  # wijk   -> polygon

sf::st_geometry_type(point)
#> [1] MULTILINESTRING
#> 18 Levels: GEOMETRY POINT LINESTRING POLYGON MULTIPOINT ... TRIANGLE
sf::st_geometry_type(road)
#> [1] MULTILINESTRING
#> 18 Levels: GEOMETRY POINT LINESTRING POLYGON MULTIPOINT ... TRIANGLE
sf::st_geometry_type(area)
#> [1] MULTIPOLYGON
#> 18 Levels: GEOMETRY POINT LINESTRING POLYGON MULTIPOINT ... TRIANGLE
```

Seen together, the three levels nest neatly — the address sits on the
road, which lies inside the district.

``` r

tm_shape(area) +
  tm_polygons(fill = "#F7F3EC", col = "grey50") +
  tm_shape(road) +
  tm_lines(col = "#1f78b4", lwd = 2) +
  tm_shape(point) +
  tm_dots(fill = "#E8631C", size = 0.6) +
  tm_title("Three search levels: district, road, address")
```

![](geocoding_files/figure-html/levels-map-1.png)

## Combine with `pdok_filter_by()`

This is where geocoding earns its place in a workflow. Many tasks start
with “the data inside *this* area” — and
[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
gives you that area as a boundary without having to find and load an
administrative layer first. A geocoded `gemeente`, `wijk` or `provincie`
polygon drops straight into `filter_by`.

``` r

boundary <- pdok_geocode("De Bilt", type = "gemeente")

# read the neighborhoods that meet the boundary, then keep those whose center
# lies inside it. A geocoded boundary is generalized, so it clips edge
# neighborhoods unevenly; `predicate = "within"` alone would drop some, while
# `"intersects"` pulls in slivers of neighboring municipalities.
buurten <- pdok_read(
  "cbs/gebiedsindelingen", "buurt_gegeneraliseerd", datetime = 2025,
  filter_by = boundary, predicate = "intersects"
)
centers <- suppressWarnings(sf::st_centroid(buurten))
buurten <- filter(buurten, lengths(sf::st_within(centers, boundary)) > 0)
nrow(buurten)
#> [1] 24
```

The geocoded boundary did the filtering; the result is every
neighborhood inside the municipality of De Bilt. On an interactive map
you can see where that is and hover for the neighborhood names:

``` r

tmap_mode("view")
#> ℹ tmap modes "plot" - "view"

tm_basemap(pdok_basemap("grijs")) +
  tm_shape(buurten) +
  tm_polygons(
    fill = "statnaam",
    fill.scale = tm_scale_categorical(values = "brewer.set3"),
    fill.legend = tm_legend(show = FALSE),
    col = "white", fill_alpha = 0.6, id = "statnaam"
  ) +
  tm_credits("Kaartgegevens © Kadaster")
```

The same pattern works for any layer: geocode the area you care about,
then read the buildings, parcels or statistics within it.

## Geocoding a whole column

[`pdok_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_geocode.md)
takes a *vector* of queries, so you can geocode a column of addresses in
one call. Every result row carries a `query` column identifying the
input it came from, which keeps the output aligned with the input — even
when a query returns several candidates, or none.

Free search ranks matches across *all* levels — the exact address, but
also the street or place it sits on — and returns the best-ranked one
per query. So keep an eye on the `type` column: below, two queries
resolve to the street (`weg`) rather than the house number, which is why
their geometry is a line, not a point.

``` r

addresses <- c("Domplein 1, Utrecht", "Coolsingel 40, Rotterdam",
               "Vrijthof 1, Maastricht")

pdok_geocode(addresses)[, c("query", "type", "weergavenaam")]
#> Simple feature collection with 3 features and 3 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 4.479201 ymin: 50.84827 xmax: 5.68912 ymax: 52.09118
#> Geodetic CRS:  WGS 84
#> # A tibble: 3 × 4
#>   query                    type  weergavenaam                           geometry
#>   <chr>                    <chr> <chr>                            <GEOMETRY [°]>
#> 1 Domplein 1, Utrecht      weg   Domplein, Utrecht     MULTILINESTRING ((5.1219…
#> 2 Coolsingel 40, Rotterdam adres Coolsingel 40, 3011A… POINT (4.479201 51.92272)
#> 3 Vrijthof 1, Maastricht   weg   Vrijthof, Maastricht  MULTILINESTRING ((5.6877…
```

Pin the level with `type` when you know what you want. `type = "adres"`
returns the exact addresses, all as points:

``` r

pdok_geocode(addresses, type = "adres")[, c("query", "type", "weergavenaam")]
#> Simple feature collection with 3 features and 3 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 4.479201 ymin: 50.84967 xmax: 5.689297 ymax: 52.09119
#> Geodetic CRS:  WGS 84
#> # A tibble: 3 × 4
#>   query                    type  weergavenaam                     geometry
#>   <chr>                    <chr> <chr>                         <POINT [°]>
#> 1 Domplein 1, Utrecht      adres Domplein 1, 3512JC U… (5.122029 52.09119)
#> 2 Coolsingel 40, Rotterdam adres Coolsingel 40, 3011A… (4.479201 51.92272)
#> 3 Vrijthof 1, Maastricht   adres Vrijthof 1, 6211LC M… (5.689297 50.84967)
```

## The other direction: reverse geocoding

Sometimes you have coordinates — GPS points, sensor locations, a spot on
a map — and want to know *what is there*.
[`pdok_reverse_geocode()`](https://coeneisma.github.io/pdokr/reference/pdok_reverse_geocode.md)
takes `sf` points and returns the nearest address, road or place, with
an `afstand` column giving the distance in meters. A `point_id` column
maps each match back to its input point.

``` r

points <- sf::st_sfc(
  sf::st_point(c(5.121, 52.090)),   # central Utrecht
  sf::st_point(c(4.479, 51.923)),   # central Rotterdam
  crs = 4326
)

pdok_reverse_geocode(points)[, c("point_id", "type", "weergavenaam", "afstand")]
#> Simple feature collection with 2 features and 4 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 4.478736 ymin: 51.92322 xmax: 5.120999 ymax: 52.09001
#> Geodetic CRS:  WGS 84
#> # A tibble: 2 × 5
#>   point_id type  weergavenaam                  afstand            geometry
#>      <int> <chr> <chr>                           <dbl>         <POINT [°]>
#> 1        1 adres Donkeregaard 4, 3511KW Utrec…    0.68 (5.120999 52.09001)
#> 2        2 adres Coolsingel 30, 3011AD Rotter…   30.2  (4.478736 51.92322)
```

By default it returns the nearest match of any type — usually an
address. Use `type` to choose the level: `type = "weg"` for the nearest
road, or `type = "gemeente"` for the municipality the point falls in
(distance 0, since the point is inside it).

The input can be in any CRS — RD New points work just as well; they are
converted to lon/lat for the query automatically.

## Where to next

- [Filtering data by
  area](https://coeneisma.github.io/pdokr/articles/filtering-by-area.md)
  — more on
  [`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md).
- [Mapping buildings by construction
  year](https://coeneisma.github.io/pdokr/articles/bag-buildings.md) —
  read a BAG layer inside an area.
- [PDOK
  basemaps](https://coeneisma.github.io/pdokr/articles/basemaps.md) —
  the gray background map used here, and the other styles.
