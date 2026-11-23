# A single-feature GeoJSON body whose id is taken from the item URL, so a
# response can be traced back to the link it was requested through.
href_feature <- function(url) {
  id <- sub(".*/items/([^?]+).*", "\\1", url)
  sprintf(
    '{"type":"Feature","id":"%s","properties":{"identificatie":"%s","bouwjaar":1900},"geometry":{"type":"Point","coordinates":[5.1,52.1]}}',
    id, id
  )
}

mock_href <- function(status = 200) {
  function(req) {
    if (!grepl("/collections/[^/]+/items/", req$url)) {
      cli::cli_abort("Unexpected mock request: {req$url}")
    }
    httr2::response(
      status_code = status,
      url = req$url,
      headers = list(
        `Content-Type` = "application/geo+json",
        `Content-Crs` = "<http://www.opengis.net/def/crs/OGC/1.3/CRS84>"
      ),
      body = charToRaw(if (status == 200) href_feature(req$url) else "{}")
    )
  }
}

base <- "https://api.pdok.nl/kadaster/bag/ogc/v2/collections/pand/items/"

units_sf <- function() {
  x <- sf::st_sf(
    identificatie = c("a", "b", "c"),
    postcode = "3811MZ",
    geometry = sf::st_sfc(sf::st_point(c(5, 52)), sf::st_point(c(5, 52)), sf::st_point(c(5, 52)), crs = 4326)
  )
  # A list-column, as sf::read_sf() produces for a GeoJSON array property.
  x$pand.href <- list(paste0(base, "p1"), paste0(base, "p2"), paste0(base, "p1"))
  x
}

test_that("pdok_read_href attaches the linked feature to every row, reading each link once", {
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_href()(req)
  })

  out <- pdok_read_href(units_sf(), "pand.href")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L) # one row per unit, as in x
  expect_equal(length(urls), 2L) # p1 is linked twice but read once
  expect_equal(
    names(out),
    c("identificatie", "postcode", "pand.href", "id", "pand.identificatie", "bouwjaar", "geometry")
  )
  expect_equal(out$identificatie, c("a", "b", "c"))
  expect_type(out$pand.href, "character")
  expect_equal(out$pand.href, paste0(base, c("p1", "p2", "p1")))
  expect_equal(out$pand.identificatie, c("p1", "p2", "p1"))
  expect_equal(out$bouwjaar, rep(1900, 3))
  # The geometry is the linked feature's, not the unit's own point.
  expect_equal(sf::st_coordinates(out)[1, ], c(X = 5.1, Y = 52.1))
  expect_equal(sf::st_crs(out)$epsg, 4326L)
})

test_that("pdok_read_href accepts the layer name and finds a single link column itself", {
  httr2::local_mocked_responses(mock_href())

  expect_equal(nrow(pdok_read_href(units_sf(), "pand")), 3L)
  expect_equal(nrow(pdok_read_href(units_sf())), 3L)
})

test_that("pdok_read_href expands rows with several links", {
  httr2::local_mocked_responses(mock_href())
  x <- units_sf()
  x$pand.href[[1]] <- paste0(base, c("p1", "p9"))

  out <- pdok_read_href(x, "pand", crs = 28992)
  expect_equal(nrow(out), 4L)
  expect_equal(out$identificatie, c("a", "a", "b", "c"))
  expect_equal(out$pand.identificatie, c("p1", "p9", "p2", "p1"))
  expect_equal(sf::st_crs(out)$epsg, 28992L)
})

test_that("pdok_read_href keeps a selection of columns", {
  httr2::local_mocked_responses(mock_href())

  out <- pdok_read_href(units_sf(), "pand", keep = "postcode")
  expect_equal(
    names(out),
    c("postcode", "pand.href", "id", "identificatie", "bouwjaar", "geometry")
  )
  expect_equal(out$identificatie, c("p1", "p2", "p1")) # no clash, so no prefix
  expect_error(pdok_read_href(units_sf(), "pand", keep = "nope"), "nope")
  expect_error(pdok_read_href(units_sf(), "pand", keep = 1), "keep")
})

test_that("pdok_read_href drops rows without a link, with a warning", {
  httr2::local_mocked_responses(mock_href())
  x <- units_sf()
  x$pand.href[[2]] <- character()

  expect_warning(out <- pdok_read_href(x, "pand"), "1 row of `x` has no link")
  expect_equal(out$identificatie, c("a", "c"))
})

test_that("pdok_read_href returns the distinct linked features with keep = FALSE", {
  httr2::local_mocked_responses(mock_href())

  out <- pdok_read_href(units_sf(), "pand", keep = FALSE)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)
  expect_equal(names(out)[1], "href")
  expect_setequal(out$href, paste0(base, c("p1", "p2")))
  expect_equal(out$identificatie[out$href == paste0(base, "p2")], "p2")
})

test_that("pdok_read_href reads a character vector of links", {
  httr2::local_mocked_responses(mock_href())

  out <- pdok_read_href(paste0(base, c("x", "y", "z", "x")))
  expect_equal(nrow(out), 3L)
  expect_equal(names(out)[1], "href")
})

test_that("pdok_read_href explains a missing or wrong column", {
  x <- units_sf()
  x$verblijfsobject.href <- list("a", "b", "c")
  expect_error(pdok_read_href(x), "must name the link column")
  expect_error(pdok_read_href(units_sf(), "woonplaats"), "pand.href")
  no_links <- units_sf()[, "identificatie"]
  expect_error(pdok_read_href(no_links, "pand"), "no column ending in")
  expect_error(pdok_read_href(no_links), "no column ending in")
})

test_that("pdok_read_href validates its input", {
  expect_error(pdok_read_href(1), "character vector")
  expect_error(pdok_read_href(c("not a url")), "feature URLs")
  expect_error(pdok_read_href(paste0(base, "p1"), max_active = 0), "max_active")
  expect_error(pdok_read_href(paste0(base, "p1"), rate = -1), "rate")
})

test_that("pdok_read_href warns and returns an empty sf without links", {
  x <- units_sf()
  x$pand.href <- list(character(), NA_character_, "")
  expect_warning(out <- pdok_read_href(x, "pand"), "no links")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
})

test_that("pdok_read_href fails clearly when a link cannot be read", {
  httr2::local_mocked_responses(mock_href(status = 404))
  expect_error(
    pdok_read_href(paste0(base, c("p1", "p2"))),
    "2 of 2 linked features could not be read"
  )
})
