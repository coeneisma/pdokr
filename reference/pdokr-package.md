# pdokr: Access Open Geodata from the Dutch 'PDOK' Platform

Tools to discover, download, and spatially filter open geographic data
from 'PDOK' (Publieke Dienstverlening Op de Kaart), the national geodata
platform of the Netherlands. Datasets and their layers are searched and
loaded as vector simple feature ('sf') objects through 'OGC' API
Features endpoints, with automatic pagination and explicit coordinate
reference system handling. Loaded layers can be filtered by any polygon
area, and addresses or place names can be geocoded through the 'PDOK'
location server. The focus is on vector feature data; raster, tile, and
coverage services are out of scope. See <https://www.pdok.nl/> for more
information about the platform and its services.

## Details

`pdokr` is a client for PDOK's **OGC API Features** services. It reads
*vector* feature data — points, lines, and polygons — and returns it as
[sf](https://r-spatial.github.io/sf/reference/sf.html) objects. Raster,
tile, and coverage services (such as elevation grids or map-tile
backgrounds) are out of scope:
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)
loads features only. A handful of datasets listed by
[`pdok_list_datasets()`](https://coeneisma.github.io/pdokr/reference/pdok_list_datasets.md)
serve tiles or coverages rather than features; those cannot be read as
`sf`, and
[`pdok_read()`](https://coeneisma.github.io/pdokr/reference/pdok_read.md)
reports this clearly. For the official PDOK map background, use
[`pdok_basemap()`](https://coeneisma.github.io/pdokr/reference/pdok_basemap.md).

## See also

Useful links:

- <https://github.com/coeneisma/pdokr>

- <https://coeneisma.github.io/pdokr/>

- Report bugs at <https://github.com/coeneisma/pdokr/issues>

## Author

**Maintainer**: Coen Eisma <coeneisma@gmail.com>
([ORCID](https://orcid.org/0009-0007-9001-2572)) \[copyright holder\]

Authors:

- Coen Eisma <coeneisma@gmail.com>
  ([ORCID](https://orcid.org/0009-0007-9001-2572)) \[copyright holder\]
