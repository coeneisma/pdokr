# Search PDOK datasets

Filters the dataset registry from
[`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
by a case-insensitive partial match. The query is matched against each
dataset's identifier, name, description, and keywords.

## Usage

``` r
pdok_search_datasets(query)
```

## Arguments

- query:

  A single non-empty string to search for, e.g. `"gemeente"`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with the
same columns as
[`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md),
containing only the matching rows (zero rows when nothing matches).

## See also

[`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
for the full list.

## Examples

``` r
# \donttest{
pdok_search_datasets("gemeente")
#> # A tibble: 14 × 7
#>    id                          name  description keywords services owner ogc_url
#>    <chr>                       <chr> <chr>       <list>   <chr>    <chr> <chr>  
#>  1 kadaster/brk-administratie… Admi… Overzicht … <chr>    ogc      kada… https:…
#>  2 ienw/agglomeraties-omgevin… Aggl… Gegevens o… <chr>    ogc      ienw  https:…
#>  3 kadaster/brk-bestuurlijke-… Best… Overzicht … <chr>    ogc      kada… https:…
#>  4 cbs/gebiedsindelingen-hist… CBS … Deze servi… <chr>    ogc      cbs   https:…
#>  5 cbs/gebiedsindelingen       CBS … Deze servi… <chr>    ogc      cbs   https:…
#>  6 cbs/wijken-en-buurten-2022  CBS … Het Bestan… <chr>    ogc      cbs   https:…
#>  7 cbs/wijken-en-buurten-2023  CBS … Het Bestan… <chr>    ogc      cbs   https:…
#>  8 cbs/wijken-en-buurten-2024  CBS … Het Bestan… <chr>    ogc      cbs   https:…
#>  9 cbs/wijken-en-buurten-2025  CBS … Het Bestan… <chr>    ogc      cbs   https:…
#> 10 cbs/wijken-en-buurten-hist… CBS … Het CBS Wi… <chr>    ogc      cbs   https:…
#> 11 rws/nationaal-wegenbestand… NWB … Dit is de … <chr>    ogc      rws   https:…
#> 12 rvo/potentiekaart-omgeving… Pote… De WarmteA… <chr>    ogc      rvo   https:…
#> 13 rvo/potentiekaart-reststro… Pote… De WarmteA… <chr>    ogc      rvo   https:…
#> 14 cbs/statistical-units-vect… Stat… This datas… <chr>    ogc      cbs   https:…
# }
```
