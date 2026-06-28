# Combining with external data: school locations (DUO)

PDOK is rarely the only source you need. A common pattern is to take a
table from another open API, turn it into spatial data, and combine it
with authoritative PDOK geometry. This article does that with
[DUO](https://duo.nl/)’s open data on schools — and shows that combining
sources often means a little data wrangling first.

``` r

library(pdokr)
library(tmap)
library(sf)
#> Linking to GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0; sf_use_s2() is TRUE
library(jsonlite)
```

DUO publishes its data through a [CKAN open-data
API](https://onderwijsdata.duo.nl/). Every table is one resource; this
small helper fetches one as a data frame.

``` r

read_duo <- function(resource_id) {
  url <- paste0(
    "https://onderwijsdata.duo.nl/api/3/action/datastore_search",
    "?resource_id=", resource_id, "&limit=50000"
  )
  # the responses are large, so download to a file and retry if one drops
  for (attempt in 1:4) {
    tmp <- tempfile(fileext = ".json")
    ok <- tryCatch({ download.file(url, tmp, quiet = TRUE); TRUE },
                   error = function(e) FALSE)
    if (ok) return(fromJSON(tmp)$result$records)
    Sys.sleep(2)
  }
  stop("DUO request failed after several attempts")
}
```

## 1. Fetch the education locations

The `onderwijslocaties` resource lists every location where education
*may* take place, each with coordinates and a `BAG_ID`.

``` r

locations <- read_duo("a7e3f323-6e46-4dca-a834-369d9d520aa8")
nrow(locations)
#> [1] 13597
```

There is a catch: these are *possible* education locations, not
recognised schools. A conference centre that hosts the odd exam, or a
commercial training firm, is in here too. Mapping them straight away
would put dots where no school exists.

## 2. Keep only the recognised schools

To find the schools recognised in law we combine two more DUO tables.
The `relaties...` resource links a location (`ONDERWIJSLOCATIECODE`) to
a recognised institution (`VESTIGINGSCODE`); the `vestigingserkenningen`
resource describes that institution — its name and the education law it
falls under (`WET`). Both tables are historical, so a row counts only
when it has no `EINDDATUM`.

``` r

relations    <- read_duo("c18ec7dd-aa4e-4b51-997c-782955f1aa38")
institutions <- read_duo("01fd2a5f-40af-456f-864d-13265a51e5e2")

# keep only currently valid rows (no end date)
relations    <- relations[is.na(relations$EINDDATUM), ]
institutions <- institutions[is.na(institutions$EINDDATUM), ]
institutions <- institutions[!duplicated(institutions$VESTIGINGSCODE), ]

# translate the education-law code into a readable sector
sectors <- c(WPO = "Primary", WVO = "Secondary", WEC = "Special",
             WEB = "Vocational (MBO)", WHW = "Higher education")
institutions$sector <- sectors[institutions$WET]

# location -> recognised institution -> sector and name (one per location)
link <- merge(
  relations[, c("ONDERWIJSLOCATIECODE", "VESTIGINGSCODE")],
  institutions[, c("VESTIGINGSCODE", "sector", "VOLLEDIGE_NAAM")],
  by = "VESTIGINGSCODE"
)
link <- link[!duplicated(link$ONDERWIJSLOCATIECODE), ]
names(link)[names(link) == "VOLLEDIGE_NAAM"] <- "school"

# inner join drops every location without a recognised institution
schools <- merge(locations, link, by = "ONDERWIJSLOCATIECODE")
nrow(schools)
#> [1] 9675
table(schools$sector)
#> 
#> Higher education          Primary        Secondary          Special 
#>               62             7249             1450              712 
#> Vocational (MBO) 
#>              202
```

Only the locations backed by a recognised institution remain — no
training venues, no exam halls — and each carries its school name and
education sector.

One quirk worth knowing: a university or college is registered as a
*single* recognised institution, so only its official location appears
here, not its every building. The map below is therefore dominated by
primary and secondary schools, which register each site.

## 3. Make it spatial and combine with PDOK

The coordinates are WGS84 longitude/latitude, so we build an `sf` object
and use
[`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md)
with a municipal boundary to zoom in on Utrecht.

``` r

schools <- schools[!is.na(schools$GPS_LONGITUDE) & !is.na(schools$GPS_LATITUDE), ]
schools <- st_as_sf(
  schools, coords = c("GPS_LONGITUDE", "GPS_LATITUDE"), crs = 4326
)

gemeenten <- pdok_read(
  "cbs/gebiedsindelingen", "gemeente_gegeneraliseerd", datetime = 2025
)
utrecht <- gemeenten[gemeenten$statnaam == "Utrecht", ]

utrecht_schools <- pdok_filter_by(schools, utrecht, predicate = "within")
nrow(utrecht_schools)
#> [1] 186
```

``` r

tmap_mode("plot")
#> ℹ tmap modes "plot" - "view"
#> ℹ toggle with `tmap::ttm()`

tm_shape(utrecht) +
  tm_polygons(fill = "grey95", col = "grey60") +
  tm_shape(utrecht_schools) +
  tm_dots(
    fill = "sector", size = 0.5,
    fill.scale = tm_scale_categorical(values = "brewer.set2"),
    fill.legend = tm_legend("Sector")
  ) +
  tm_title("Recognised schools in Utrecht, by sector")
```

![](duo-schools_files/figure-html/map-overview-1.png)

## 4. Map the school buildings

Each school sits in a building from the BAG. We read the `pand`
(building) layer for the historic centre, keep the footprints that
contain a school, and carry the school name and sector across with a
spatial join.

``` r

wijken <- pdok_read(
  "cbs/gebiedsindelingen", "wijk_gegeneraliseerd", datetime = 2025,
  filter_by = utrecht, predicate = "within"
)
binnenstad <- wijken[grepl("Binnenstad", wijken$statnaam), ]
centre_schools <- pdok_filter_by(utrecht_schools, binnenstad, predicate = "within")

panden <- pdok_read("kadaster/bag", "pand", filter_by = binnenstad)
#> ⠙ Downloading PDOK features: 1558 fetched
#> ⠹ Downloading PDOK features: 2059 fetched
#> ⠸ Downloading PDOK features: 4011 fetched
#> ⠼ Downloading PDOK features: 6026 fetched
school_buildings <- st_filter(panden, centre_schools)
school_buildings <- st_join(
  school_buildings, centre_schools[, c("school", "sector", "STRAATNAAM")]
)
nrow(school_buildings)
#> [1] 11
```

The result is real school buildings, coloured by sector. Click one for
the school that uses it.

``` r

tmap_mode("view")
#> ℹ tmap modes "plot" - "view"

tm_basemap("CartoDB.Positron") +
  tm_shape(school_buildings) +
  tm_polygons(
    fill = "sector",
    fill.scale = tm_scale_categorical(values = "brewer.set2"),
    fill.legend = tm_legend("Sector"),
    col = "grey30", lwd = 0.5, id = "school",
    popup = tm_popup(vars = c("School" = "school", "Sector" = "sector",
                              "Street" = "STRAATNAAM"))
  )
```

## Where to next

- [Filtering data by
  area](https://coeneisma.github.io/pdokr/articles/filtering-by-area.md)
  — more on
  [`pdok_filter_by()`](https://coeneisma.github.io/pdokr/reference/pdok_filter_by.md).
- [Mapping buildings by construction
  year](https://coeneisma.github.io/pdokr/articles/bag-buildings.md) —
  another BAG example, using the `pand` (building) layer.
