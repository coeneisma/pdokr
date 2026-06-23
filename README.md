
<!-- README.md is generated from README.Rmd. Please edit that file -->

# pdokr

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/pdokr)](https://CRAN.R-project.org/package=pdokr)
[![R-CMD-check](https://github.com/coeneisma/pdokr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/coeneisma/pdokr/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`pdokr` makes it easy to work with open geographic data from
[PDOK](https://www.pdok.nl/) (Publieke Dienstverlening Op de Kaart), the
national geodata platform of the Netherlands. It helps you discover
datasets and their layers, load a layer as an
[`sf`](https://r-spatial.github.io/sf/) object (with automatic
pagination and explicit coordinate reference system handling), filter
data by any polygon area, and geocode addresses and place names.

## Installation

You can install the development version of `pdokr` from
[GitHub](https://github.com/coeneisma/pdokr) with:

``` r
# install.packages("devtools")
devtools::install_github("coeneisma/pdokr")
```

## Example

``` r
library(pdokr)

# Search for a dataset
pdok_search_datasets("nationale parken")
#> # A tibble: 3 × 7
#>   id                           name  description keywords services owner ogc_url
#>   <chr>                        <chr> <chr>       <list>   <chr>    <chr> <chr>  
#> 1 rvo/nationaal-beschermde-ge… Nati… In deze da… <chr>    ogc      rvo   https:…
#> 2 rvo/nationale-parken-geharm… Nati… In deze da… <chr>    ogc      rvo   https:…
#> 3 rvo/nationale-parken         Nati… Dit bestan… <chr>    ogc      rvo   https:…

# Load a layer as an sf object
parks <- pdok_read("rvo/nationale-parken-geharmoniseerd", "protectedsite")

# Filter to an area: the province of Utrecht, found by geocoding
utrecht <- pdok_geocode("Utrecht", type = "provincie")
pdok_filter_by(parks, utrecht)
#> Simple feature collection with 1 feature and 14 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 5.239009 ymin: 51.95757 xmax: 5.566058 ymax: 52.13387
#> Geodetic CRS:  WGS 84
#> # A tibble: 1 × 15
#>   id          gml_id language legalfoundationdate legalfoundationdocum…¹ localid
#>   <chr>       <chr>  <chr>    <chr>               <chr>                  <chr>  
#> 1 fc981af1-8… G_4a2… nld      ""                  ""                     L_4a24…
#> # ℹ abbreviated name: ¹​legalfoundationdocument
#> # ℹ 9 more variables: namespace <chr>, namestatus <chr>, nativeness <chr>,
#> #   pronunciation <chr>, script <chr>, siteprotectionclassification <chr>,
#> #   sourceofname <chr>, text <chr>, geometry <MULTIPOLYGON [°]>
```

## Learn more

See the [package website](https://coeneisma.github.io/pdokr/) for the
reference documentation and articles on getting started, filtering data
by area, working with coordinate reference systems, and querying PDOK by
hand.
