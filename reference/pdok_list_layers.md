# List the layers within a PDOK dataset

Lists the layers (OGC API Features collections) offered by a dataset.

## Usage

``` r
pdok_list_layers(dataset)
```

## Arguments

- dataset:

  A dataset id from
  [`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
  (e.g. `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per layer and the columns `dataset` (the dataset id, echoing the
input so each row works directly with
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)),
`layer` (the layer identifier), `title`, `description`, `start_date` and
`end_date` (the temporal extent the layer covers, as `Date`s; `end_date`
is `NA` when the layer is ongoing), `crs` (a list-column of available
EPSG codes), `storage_crs` (the EPSG code the data is stored in), and
`bbox` (a list-column of named numeric extents
`c(xmin, ymin, xmax, ymax)` in CRS84).

## See also

[`pdok_search_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_search_layers.md)
to filter this list,
[`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
for the datasets.

## Examples

``` r
# \donttest{
pdok_list_layers("cbs/gebiedsindelingen")
#> # A tibble: 63 × 9
#>    dataset layer title description start_date end_date crs    storage_crs bbox  
#>    <chr>   <chr> <chr> <chr>       <date>     <date>   <list>       <int> <list>
#>  1 cbs/ge… arbe… Arbe… Een indeli… 2016-01-01 NA       <int>        28992 <dbl> 
#>  2 cbs/ge… arbe… Arbe… arbeidsmar… 2016-01-01 NA       <int>        28992 <dbl> 
#>  3 cbs/ge… arro… Arro… De arrondi… 2016-01-01 NA       <int>        28992 <dbl> 
#>  4 cbs/ge… arro… Arro… arrondisse… 2016-01-01 NA       <int>        28992 <dbl> 
#>  5 cbs/ge… buur… Buur… Onderdeel … 2016-01-01 NA       <int>        28992 <dbl> 
#>  6 cbs/ge… buur… Buur… buurt_labe… 2016-01-01 NA       <int>        28992 <dbl> 
#>  7 cbs/ge… buur… Buur… buurtnietg… 2016-01-01 NA       <int>        28992 <dbl> 
#>  8 cbs/ge… coro… Coro… De COROP-g… 2016-01-01 NA       <int>        28992 <dbl> 
#>  9 cbs/ge… coro… Coro… coropgebie… 2016-01-01 NA       <int>        28992 <dbl> 
#> 10 cbs/ge… coro… Coro… De COROP-p… 2016-01-01 NA       <int>        28992 <dbl> 
#> # ℹ 53 more rows
# }
```
