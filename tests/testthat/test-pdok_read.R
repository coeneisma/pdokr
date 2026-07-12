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
  # a fractional or non-positive year is rejected up front, not silently sent
  expect_error(format_datetime(2024.5), "positive whole number")
  expect_error(format_datetime(-5), "positive whole number")
})

test_that("pdok_read returns an sf object from the OGC path", {
  httr2::local_mocked_responses(mock_pdok_dispatcher(items = items_resp(make_items_body(list(c(5, 52), c(5.1, 52.1))))))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)
  expect_equal(sf::st_crs(out)$epsg, 4326L)
})

test_that("pdok_read transforms to the requested crs", {
  httr2::local_mocked_responses(mock_pdok_dispatcher(items = items_resp(make_items_body(list(c(5.17, 52.1))))))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd", crs = 28992)
  expect_equal(sf::st_crs(out)$epsg, 28992L)
})

test_that("pdok_read trims to max_features", {
  body <- make_items_body(list(c(5, 52), c(5.1, 52.1), c(5.2, 52.2)))
  httr2::local_mocked_responses(mock_pdok_dispatcher(items = items_resp(body)))
  out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd", max_features = 1)
  expect_equal(nrow(out), 1L)
})

test_that("pdok_read warns and returns 0 rows for an empty result", {
  httr2::local_mocked_responses(mock_pdok_dispatcher(items = items_resp(make_items_body(list()))))
  expect_warning(
    out <- pdok_read("cbs/gebiedsindelingen", "gemeente_gegeneraliseerd"),
    "No features"
  )
  expect_equal(nrow(out), 0L)
})

test_that("pdok_read clips the result to filter_by", {
  body <- make_items_body(list(c(5.0, 52.0), c(5.2, 52.1), c(6.0, 53.0)))
  httr2::local_mocked_responses(mock_pdok_dispatcher(items = items_resp(body)))

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

test_that("pdok_read reports a non-Features dataset clearly", {
  fail_items <- httr2::response(
    status_code = 404,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/collections/c/items",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw("{}")
  )
  httr2::local_mocked_responses(mock_pdok_dispatcher(
    items = fail_items,
    conformance = mock_conformance_resp(features = FALSE)
  ))
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "some_layer"),
    "does not offer OGC API Features"
  )
})

test_that("pdok_read keeps the original error on a genuine Features dataset", {
  # A wrong layer id 404s, but the dataset *is* a Features API, so the tailored
  # not-Features message must not hijack the real error.
  fail_items <- httr2::response(
    status_code = 404,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/collections/c/items",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw("{}")
  )
  httr2::local_mocked_responses(mock_pdok_dispatcher(
    items = fail_items,
    conformance = mock_conformance_resp(features = TRUE)
  ))
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "no_such_layer"),
    "resource not found"
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

test_that("pdok_read validates crs before hitting the network", {
  expect_error(pdok_read("cbs/gebiedsindelingen", "x", crs = "RD"), "EPSG code")
  expect_error(pdok_read("cbs/gebiedsindelingen", "x", crs = -1), "EPSG code")
  expect_error(pdok_read("cbs/gebiedsindelingen", "x", crs = 28992.5), "EPSG code")
})

test_that("pdok_read sends bbox and datetime in the items query", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    if (grepl("/collections/[^/]+/items", req$url)) seen <<- req$url
    mock_pdok_dispatcher(
      items = items_resp(make_items_body(list(c(5, 52))))
    )(req)
  })

  pdok_read(
    "cbs/gebiedsindelingen", "gemeente_gegeneraliseerd",
    bbox = c(4.8, 51.9, 5.2, 52.1), datetime = 2024, max_features = 1
  )

  expect_match(seen, "bbox=")
  expect_match(seen, "datetime=")
  expect_match(seen, "2024-07-01")
})

test_that("pdok_read keeps the original error when Features support is undeterminable", {
  # items 404s, and /conformance returns an empty body -> support is NA, so the
  # not-Features message must not hijack the genuine 404.
  fail_items <- httr2::response(
    status_code = 404,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/collections/c/items",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw("{}")
  )
  empty_conf <- httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/conformance",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw('{"conformsTo":[]}')
  )
  httr2::local_mocked_responses(mock_pdok_dispatcher(
    items = fail_items, conformance = empty_conf
  ))
  expect_error(
    pdok_read("cbs/gebiedsindelingen", "no_such_layer"),
    "resource not found"
  )
})
