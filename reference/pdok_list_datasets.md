# List PDOK datasets

Returns the full table of contents of datasets offered through the
'PDOK' OGC API Features platform, fetched live from
<https://api.pdok.nl/index.json>.

## Usage

``` r
pdok_list_datasets()
```

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per dataset and the columns `id` (the identifier passed to
[`pdok_list_layers()`](https://coeneisma.github.io/pdokr/reference/pdok_list_layers.md)
and
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)),
`name`, `description`, `keywords` (a list-column of character vectors),
`services`, `owner`, and `ogc_url`.

## See also

[`pdok_search_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_search_datasets.md)
to filter this list.

## Examples

``` r
# \donttest{
pdok_list_datasets()
#> # A tibble: 113 × 7
#>    id                          name  description keywords services owner ogc_url
#>    <chr>                       <chr> <chr>       <list>   <chr>    <chr> <chr>  
#>  1 kadaster/3d-basisvoorzieni… 3D B… De 3D Basi… <chr>    ogc      kada… https:…
#>  2 kadaster/3d-geluid          3D G… Berekening… <chr>    ogc      kada… https:…
#>  3 kadaster/3d-basisvoorzieni… 3D T… De 3D teru… <chr>    ogc      kada… https:…
#>  4 kadaster/brk-administratie… Admi… Overzicht … <chr>    ogc      kada… https:…
#>  5 ienw/agglomeraties-omgevin… Aggl… Gegevens o… <chr>    ogc      ienw  https:…
#>  6 kadaster/bag-terugmeldingen BAG … De BAG ter… <chr>    ogc      kada… https:…
#>  7 kadaster/bgt-terugmeldingen BGT … De BGT ter… <chr>    ogc      kada… https:…
#>  8 tno/bro-grondwatermonitori… BRO … Deze datas… <chr>    ogc      tno   https:…
#>  9 kadaster/brt-achtergrondka… BRT … De BRT Ach… <chr>    ogc      kada… https:…
#> 10 kadaster/brt-top10nl        BRT … TOP10NL is… <chr>    ogc      kada… https:…
#> # ℹ 103 more rows
# }
```
