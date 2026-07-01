test_that("ahn_bbox_rd returns an RD bounding box", {
  pt <- sf::st_sfc(sf::st_point(c(155000, 463000)), crs = 28992)
  bb <- ahn_bbox_rd(sf::st_buffer(pt, 100))
  expect_s3_class(bb, "bbox")
  expect_equal(sf::st_crs(bb)$epsg, 28992L)

  # a lon/lat area is converted to RD
  ll <- sf::st_buffer(sf::st_sfc(sf::st_point(c(5.12, 52.09)), crs = 4326), 0.001)
  expect_equal(sf::st_crs(ahn_bbox_rd(ll))$epsg, 28992L)
})

test_that("ahn_bbox_rd rejects non-spatial input and missing CRS", {
  expect_error(ahn_bbox_rd(1), "must be")
  nocrs <- sf::st_sfc(sf::st_point(c(155000, 463000)))
  expect_error(ahn_bbox_rd(nocrs), "no CRS")
})

test_that("pdok_ahn validates its arguments", {
  skip_if_not_installed("terra")
  expect_error(pdok_ahn(1), "must be")                 # bad area
  area <- sf::st_buffer(sf::st_sfc(sf::st_point(c(155000, 463000)), crs = 28992), 100)
  expect_error(pdok_ahn(area, model = "nope"))         # bad model
})

test_that("pdok_ahn guards against too-large areas (no network)", {
  skip_if_not_installed("terra")
  big <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 150000, ymin = 460000, xmax = 156000, ymax = 466000), crs = 28992
  ))
  expect_error(pdok_ahn(big), "too large")
})

test_that("pdok_ahn downloads AHN as a SpatRaster (online safety net)", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not_installed("terra")

  area <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 155000, ymin = 463000, xmax = 155150, ymax = 463150), crs = 28992
  ))
  r <- pdok_ahn(area, "dtm")

  expect_s4_class(r, "SpatRaster")
  expect_equal(terra::res(r)[1], 0.5)
  expect_equal(terra::crs(r, describe = TRUE)$code, "28992")
  vals <- terra::values(r)
  expect_true(all(vals > -10 & vals < 350, na.rm = TRUE))  # plausible NL heights
})
