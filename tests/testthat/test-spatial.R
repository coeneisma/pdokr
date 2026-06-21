# A small square in RD New (EPSG:28992) around De Bilt (centre ~140220, 457559).
rd_square <- function(cx = 140220, cy = 457559, half = 500) {
  m <- matrix(
    c(cx - half, cy - half,
      cx + half, cy - half,
      cx + half, cy + half,
      cx - half, cy + half,
      cx - half, cy - half),
    ncol = 2, byrow = TRUE
  )
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(m)), crs = 28992))
}

test_that("as_bbox_crs84 passes a numeric CRS84 vector through", {
  res <- as_bbox_crs84(c(5, 52, 5.5, 52.5))
  expect_equal(unname(res), c(5, 52, 5.5, 52.5))
  expect_named(res, c("xmin", "ymin", "xmax", "ymax"))
})

test_that("as_bbox_crs84 transforms an sf extent from RD New to CRS84", {
  res <- as_bbox_crs84(rd_square())
  expect_named(res, c("xmin", "ymin", "xmax", "ymax"))
  # De Bilt lies near 5.17 E, 52.11 N.
  expect_true(res[["xmin"]] > 5.1 && res[["xmax"]] < 5.25)
  expect_true(res[["ymin"]] > 52.0 && res[["ymax"]] < 52.2)
  expect_true(res[["xmin"]] < res[["xmax"]])
  expect_true(res[["ymin"]] < res[["ymax"]])
})

test_that("as_bbox_crs84 accepts sfc and bbox inputs equivalently", {
  sq <- rd_square()
  from_sf  <- as_bbox_crs84(sq)
  from_sfc <- as_bbox_crs84(sf::st_geometry(sq))
  from_bb  <- as_bbox_crs84(sf::st_bbox(sq))
  expect_equal(from_sfc, from_sf)
  expect_equal(from_bb, from_sf)
})

test_that("as_bbox_crs84 errors on unknown CRS", {
  sq <- rd_square()
  sf::st_crs(sq) <- NA
  expect_error(as_bbox_crs84(sq), "coordinate reference system is unknown")
})

test_that("as_bbox_crs84 errors on bad numeric or wrong type", {
  expect_error(as_bbox_crs84(c(1, 2, 3)), "four finite values")
  expect_error(as_bbox_crs84(c(5, 52, 4, 51)), "xmin <= xmax")
  expect_error(as_bbox_crs84(list(1, 2, 3, 4)), "must be a numeric vector")
})

test_that("crs_to_uri formats an EPSG code", {
  expect_equal(crs_to_uri(28992), "http://www.opengis.net/def/crs/EPSG/0/28992")
  expect_equal(crs_to_uri(4326), "http://www.opengis.net/def/crs/EPSG/0/4326")
})

test_that("crs_to_uri validates its input", {
  expect_error(crs_to_uri("28992"), "single positive EPSG code")
  expect_error(crs_to_uri(c(1, 2)), "single positive EPSG code")
  expect_error(crs_to_uri(-1), "single positive EPSG code")
  expect_error(crs_to_uri(NA), "single positive EPSG code")
})

test_that("parse_content_crs reads EPSG and CRS84 headers", {
  expect_equal(
    parse_content_crs("<http://www.opengis.net/def/crs/EPSG/0/28992>"),
    28992L
  )
  expect_equal(
    parse_content_crs("http://www.opengis.net/def/crs/OGC/1.3/CRS84"),
    4326L
  )
  expect_equal(
    parse_content_crs("http://www.opengis.net/def/crs/EPSG/0/4258"),
    4258L
  )
})

test_that("parse_content_crs returns NULL for missing or unknown headers", {
  expect_null(parse_content_crs(NULL))
  expect_null(parse_content_crs(""))
  expect_null(parse_content_crs("not-a-crs"))
})
