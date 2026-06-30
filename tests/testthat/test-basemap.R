test_that("raster basemaps return a WMTS tile-URL template", {
  url <- pdok_basemap()
  expect_equal(url, pdok_basemap("standaard"))
  expect_match(url, "brt/achtergrondkaart/wmts")
  expect_match(url, "EPSG:3857/\\{z\\}/\\{x\\}/\\{y\\}.png$")
})

test_that("luchtfoto uses the aerial imagery service", {
  url <- pdok_basemap("luchtfoto")
  expect_match(url, "luchtfotorgb")
  expect_match(url, "\\.jpeg$")
})

test_that("each raster style maps to its own URL", {
  for (s in c("grijs", "pastel", "water")) {
    expect_match(pdok_basemap(s), paste0("/", s, "/"))
  }
})

test_that("vector basemaps return a Mapbox GL style URL", {
  url <- pdok_basemap("standaard", format = "vector")
  expect_match(url, "ogc/v1/styles/standaard__webmercatorquad\\?f=mapbox$")
  expect_match(pdok_basemap("darkmode", format = "vector"), "darkmode__webmercatorquad")
})

test_that("an unknown style errors with the valid options", {
  expect_error(pdok_basemap("nope"), "valid raster")
  # 'grijs' is a raster style, not a vector one
  expect_error(pdok_basemap("grijs", format = "vector"), "valid vector")
})

test_that("style must be a single string", {
  expect_error(pdok_basemap(c("a", "b")), "single string")
})

test_that("every basemap URL is reachable (online safety net)", {
  skip_on_cran()
  skip_if_offline()

  reachable <- function(url) {
    resp <- httr2::req_perform(
      httr2::req_error(httr2::request(url), is_error = function(resp) FALSE)
    )
    httr2::resp_status(resp)
  }

  # raster: substitute a real tile for the {z}/{x}/{y} placeholders
  for (s in names(pdok_basemap_raster)) {
    tile <- gsub("\\{z\\}/\\{x\\}/\\{y\\}", "10/525/336", pdok_basemap(s))
    expect_equal(reachable(tile), 200L, info = paste("raster", s))
  }

  # vector: the style URL is fetchable directly
  for (s in names(pdok_basemap_vector)) {
    expect_equal(reachable(pdok_basemap(s, "vector")), 200L, info = paste("vector", s))
  }
})
