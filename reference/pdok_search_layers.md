# Search the layers within a PDOK dataset

Filters the layers from
[`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md)
by a case-insensitive partial match against each layer's identifier,
title, and description.

## Usage

``` r
pdok_search_layers(dataset, query)
```

## Arguments

- dataset:

  A dataset id from
  [`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
  (e.g. `"cbs/gebiedsindelingen"`), or a raw OGC API base URL.

- query:

  A single non-empty string to search for, e.g. `"gemeente"`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with the
same columns as
[`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md),
containing only the matching rows (zero rows when nothing matches).

## See also

[`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md)
for the full list.

## Examples

``` r
# \donttest{
pdok_search_layers("cbs/gebiedsindelingen", "gemeente")
#> # A tibble: 18 × 9
#>    dataset layer title description start_date end_date crs    storage_crs bbox  
#>    <chr>   <chr> <chr> <chr>       <date>     <date>   <list>       <int> <list>
#>  1 cbs/ge… arbe… Arbe… Een indeli… 2016-01-01 NA       <int>        28992 <dbl> 
#>  2 cbs/ge… arro… Arro… De arrondi… 2016-01-01 NA       <int>        28992 <dbl> 
#>  3 cbs/ge… buur… Buur… Onderdeel … 2016-01-01 NA       <int>        28992 <dbl> 
#>  4 cbs/ge… coro… Coro… De COROP-g… 2016-01-01 NA       <int>        28992 <dbl> 
#>  5 cbs/ge… geme… Geme… De kleinst… 2016-01-01 NA       <int>        28992 <dbl> 
#>  6 cbs/ge… geme… Geme… gemeente_l… 2016-01-01 NA       <int>        28992 <dbl> 
#>  7 cbs/ge… geme… Geme… gemeenteni… 2016-01-01 NA       <int>        28992 <dbl> 
#>  8 cbs/ge… ggdr… Ggdr… Een in 199… 2016-01-01 NA       <int>        28992 <dbl> 
#>  9 cbs/ge… jeug… Jeug… Een door g… 2016-01-01 NA       <int>        28992 <dbl> 
#> 10 cbs/ge… land… Land… Een cluste… 2016-01-01 NA       <int>        28992 <dbl> 
#> 11 cbs/ge… rpag… RPA-… In het Reg… 2016-01-01 NA       <int>        28992 <dbl> 
#> 12 cbs/ge… regi… Regi… In RMC-reg… 2016-01-01 NA       <int>        28992 <dbl> 
#> 13 cbs/ge… regi… Regi… In het kad… 2016-01-01 NA       <int>        28992 <dbl> 
#> 14 cbs/ge… toer… Toer… De indelin… 2016-01-01 NA       <int>        28992 <dbl> 
#> 15 cbs/ge… toer… Toer… Lokaliseri… 2016-01-01 NA       <int>        28992 <dbl> 
#> 16 cbs/ge… veil… Veil… Een indeli… 2016-01-01 NA       <int>        28992 <dbl> 
#> 17 cbs/ge… wijk… Wijk… Onderdeel … 2016-01-01 NA       <int>        28992 <dbl> 
#> 18 cbs/ge… zorg… Zorg… Een zorgka… 2016-01-01 NA       <int>        28992 <dbl> 
# }
```
