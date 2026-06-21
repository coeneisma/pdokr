three_points_4326 <- function() {
  pts <- sf::st_sfc(
    sf::st_point(c(5.0, 52.0)),
    sf::st_point(c(5.2, 52.1)),
    sf::st_point(c(6.0, 53.0)),
    crs = 4326
  )
  sf::st_sf(id = 1:3, geometry = pts)
}

box_4326 <- function() {
  sf::st_as_sfc(
    sf::st_bbox(c(xmin = 4.9, ymin = 51.9, xmax = 5.3, ymax = 52.2), crs = 4326)
  )
}

test_that("pdok_filter_by keeps only features within the polygon", {
  res <- pdok_filter_by(three_points_4326(), box_4326(), predicate = "within")
  expect_s3_class(res, "sf")
  expect_equal(res$id, c(1L, 2L))
})

test_that("pdok_filter_by reconciles differing CRS", {
  data <- three_points_4326()
  filter_rd <- sf::st_transform(box_4326(), 28992)
  res <- pdok_filter_by(data, filter_rd, predicate = "within")
  expect_equal(res$id, c(1L, 2L))
  expect_equal(sf::st_crs(res), sf::st_crs(data))
})

test_that("pdok_filter_by returns 0 rows for empty input", {
  empty <- three_points_4326()[0, ]
  res <- pdok_filter_by(empty, box_4326())
  expect_equal(nrow(res), 0L)
})

test_that("pdok_filter_by validates its inputs", {
  expect_error(pdok_filter_by(data.frame(x = 1), box_4326()), "must be an")
  expect_error(pdok_filter_by(three_points_4326(), "nope"), "must be an")
  expect_error(
    pdok_filter_by(three_points_4326(), box_4326(), predicate = "nonsense"),
    "must be one of"
  )
})
