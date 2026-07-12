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

test_that("as_bbox_crs84 pads a degenerate (point) bbox", {
  pt <- sf::st_sfc(sf::st_point(c(5.171, 52.106)), crs = 4326)
  res <- as_bbox_crs84(pt)
  expect_gt(res[["xmax"]], res[["xmin"]])
  expect_gt(res[["ymax"]], res[["ymin"]])
})

test_that("as_bbox_crs84 handles an already lon/lat input without lwgeom", {
  poly <- sf::st_as_sfc(
    sf::st_bbox(c(xmin = 4.9, ymin = 51.9, xmax = 5.3, ymax = 52.2), crs = 4326)
  )
  res <- as_bbox_crs84(poly)
  expect_equal(unname(res), c(4.9, 51.9, 5.3, 52.2))
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

test_that("as_bbox_crs84 pads a degenerate numeric point-bbox", {
  # A point given as xmin==xmax, ymin==ymax must be widened, or the OGC bbox
  # query is rejected by the server with HTTP 400.
  out <- as_bbox_crs84(c(5, 52, 5, 52))
  expect_gt(out[["xmax"]], out[["xmin"]])
  expect_gt(out[["ymax"]], out[["ymin"]])
})

test_that("check_crs validates an EPSG code", {
  expect_equal(check_crs(28992), 28992L)
  expect_equal(check_crs(4326), 4326L)
  expect_error(check_crs("28992"), "single positive EPSG code")
  expect_error(check_crs(c(1, 2)), "single positive EPSG code")
  expect_error(check_crs(-1), "single positive EPSG code")
  expect_error(check_crs(NA), "single positive EPSG code")
  expect_error(check_crs(28992.5), "single positive EPSG code")
})

test_that("check_count validates a positive whole number", {
  expect_equal(check_count(5, "limit"), 5L)
  expect_null(check_count(NULL, "max_features", allow_null = TRUE))
  expect_error(check_count(NULL, "limit"), "single positive whole number")
  expect_error(check_count(0, "limit"), "single positive whole number")
  expect_error(check_count(2.5, "limit"), "single positive whole number")
  expect_error(check_count(-1, "limit"), "single positive whole number")
  # allow_null message advertises NULL; the plain one does not.
  expect_error(check_count("x", "max_features", allow_null = TRUE), "`NULL`")
  expect_error(check_count(0, "max_features"), "max_features")
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
