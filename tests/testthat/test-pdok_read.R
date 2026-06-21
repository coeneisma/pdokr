make_items_body <- function(points, next_url = NULL) {
  feats <- vapply(seq_along(points), function(i) {
    p <- points[[i]]
    sprintf(
      '{"type":"Feature","properties":{"id":%d},"geometry":{"type":"Point","coordinates":[%s,%s]}}',
      i, format(p[1]), format(p[2])
    )
  }, character(1))
  links <- if (is.null(next_url)) '"links":[],' else sprintf('"links":[{"rel":"next","href":"%s"}],', next_url)
  sprintf('{"type":"FeatureCollection",%s"features":[%s]}', links, paste(feats, collapse = ","))
}

items_resp <- function(json, crs = "<http://www.opengis.net/def/crs/OGC/1.3/CRS84>") {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/collections/c/items",
    headers = list(`Content-Type` = "application/geo+json", `Content-Crs` = crs),
    body = charToRaw(json)
  )
}

test_that("format_datetime handles years, strings and bad input", {
  # An integer year maps to a mid-year instant (1 July), which falls inside
  # annual validity periods such as CBS boundaries.
  expect_equal(format_datetime(2026), "2026-07-01T00:00:00Z")
  expect_equal(format_datetime("2020-01-01/2025-12-31"), "2020-01-01/2025-12-31")
  expect_error(format_datetime(TRUE), "single year")
  expect_error(format_datetime(c(2020, 2021)), "single year")
})

test_that("pdok_read returns an sf object from the OGC path", {
  httr2::local_mocked_responses(list(items_resp(make_items_body(list(c(5, 52), c(5.1, 52.1))))))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)
  expect_equal(sf::st_crs(out)$epsg, 4326L)
})

test_that("pdok_read transforms to the requested crs", {
  httr2::local_mocked_responses(list(items_resp(make_items_body(list(c(5.17, 52.1))))))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd", crs = 28992)
  expect_equal(sf::st_crs(out)$epsg, 28992L)
})

test_that("pdok_read trims to max_features", {
  body <- make_items_body(list(c(5, 52), c(5.1, 52.1), c(5.2, 52.2)))
  httr2::local_mocked_responses(list(items_resp(body)))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd", max_features = 1)
  expect_equal(nrow(out), 1L)
})

test_that("pdok_read warns and returns 0 rows for an empty result", {
  httr2::local_mocked_responses(list(items_resp(make_items_body(list()))))
  expect_warning(
    out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd"),
    "No features"
  )
  expect_equal(nrow(out), 0L)
})

test_that("pdok_read clips the result to filter_by", {
  body <- make_items_body(list(c(5.0, 52.0), c(5.2, 52.1), c(6.0, 53.0)))
  httr2::local_mocked_responses(list(items_resp(body)))

  poly <- sf::st_as_sfc(
    sf::st_bbox(c(xmin = 4.9, ymin = 51.9, xmax = 5.3, ymax = 52.2), crs = 4326)
  )
  out <- pdok_read("cbs/gebiedsindelingen", "x", filter_by = poly)
  expect_equal(nrow(out), 2L)
})

test_that("pdok_read rejects a non-spatial filter_by", {
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "x", filter_by = "nope"),
    "must be an"
  )
})

test_that("pdok_read validates layer and max_features", {
  expect_error(pdok_read("cbs/gebiedsindelingen", 1), "single non-empty string")
  expect_error(pdok_read("cbs/gebiedsindelingen", ""), "single non-empty string")
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "x", max_features = -1),
    "positive whole number"
  )
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "x", max_features = 2.5),
    "positive whole number"
  )
})

test_that("pdok_read works over WFS (integration)", {
  skip_on_cran()
  skip_if_offline()
  # Opt-in: hits the live BAG WFS, whose GetCapabilities is large and slow.
  skip_if_not(
    nzchar(Sys.getenv("PDOKR_TEST_WFS")),
    "set PDOKR_TEST_WFS to run the WFS integration test"
  )
  out <- pdok_read(
    "https://service.pdok.nl/lv/bag/wfs/v2_0",
    layer = "bag:pand",
    max_features = 1
  )
  expect_s3_class(out, "sf")
  expect_lte(nrow(out), 1L)
})
