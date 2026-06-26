# Helpers to build mock GeoJSON pages and responses.
make_fc <- function(points, next_url = NULL) {
  feats <- vapply(seq_along(points), function(i) {
    p <- points[[i]]
    sprintf(
      '{"type":"Feature","properties":{"id":%d},"geometry":{"type":"Point","coordinates":[%s,%s]}}',
      i, format(p[1]), format(p[2])
    )
  }, character(1))
  links <- if (is.null(next_url)) {
    '"links":[],'
  } else {
    sprintf('"links":[{"rel":"next","href":"%s"}],', next_url)
  }
  sprintf('{"type":"FeatureCollection",%s"features":[%s]}',
          links, paste(feats, collapse = ","))
}

mock_resp <- function(json, crs = "<http://www.opengis.net/def/crs/OGC/1.3/CRS84>") {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    headers = list(`Content-Type` = "application/geo+json", `Content-Crs` = crs),
    body = charToRaw(json)
  )
}

test_that("pdok_request assembles url, query and user-agent", {
  req <- pdok_request(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json", limit = 10, bbox = NULL)
  )
  expect_match(req$url, "f=json")
  expect_match(req$url, "limit=10")
  expect_false(grepl("bbox", req$url))
  expect_equal(req$options$useragent, "pdokr (https://github.com/coeneisma/pdokr)")
})

test_that("paginate_ogc follows next links across pages", {
  p1 <- make_fc(list(c(5, 52), c(5.1, 52.1)),
                next_url = "https://api.pdok.nl/x/ogc/v1/collections/c/items?cursor=abc")
  p2 <- make_fc(list(c(5.2, 52.2)))
  httr2::local_mocked_responses(list(mock_resp(p1), mock_resp(p2)))

  res <- paginate_ogc(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json")
  )
  expect_s3_class(res, "sf")
  expect_equal(nrow(res), 3L)
  expect_equal(sf::st_crs(res)$epsg, 4326L)
})

test_that("paginate_ogc stops at max_features (raw features)", {
  p1 <- make_fc(list(c(5, 52), c(5.1, 52.1)),
                next_url = "https://api.pdok.nl/x/ogc/v1/collections/c/items?cursor=abc")
  p2 <- make_fc(list(c(5.2, 52.2)))
  httr2::local_mocked_responses(list(mock_resp(p1), mock_resp(p2)))

  res <- paginate_ogc(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json"),
    max_features = 2
  )
  expect_equal(nrow(res), 2L)
})

test_that("paginate_ogc stops on the KEPT count when process filters", {
  # Each page has 2 features; `process` keeps only the first of each page.
  p1 <- make_fc(list(c(5, 52), c(5.1, 52.1)),
                next_url = "https://api.pdok.nl/x/ogc/v1/collections/c/items?cursor=abc")
  p2 <- make_fc(list(c(5.2, 52.2), c(5.3, 52.3)))
  httr2::local_mocked_responses(list(mock_resp(p1), mock_resp(p2)))

  res <- paginate_ogc(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json"),
    max_features = 2,
    process = function(page) page[1, , drop = FALSE]
  )
  # 1 kept per page, so it must fetch both pages to reach 2 (not stop after one).
  expect_equal(nrow(res), 2L)
})

test_that("paginate_ogc handles an empty collection", {
  httr2::local_mocked_responses(list(mock_resp(make_fc(list()))))
  res <- paginate_ogc(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json")
  )
  expect_s3_class(res, "sf")
  expect_equal(nrow(res), 0L)
})

test_that("paginate_ogc reads Content-Crs from the first response", {
  p <- make_fc(list(c(140220, 457559)))
  httr2::local_mocked_responses(
    list(mock_resp(p, crs = "<http://www.opengis.net/def/crs/EPSG/0/28992>"))
  )
  res <- paginate_ogc(
    "https://api.pdok.nl/x/ogc/v1/collections/c/items",
    query = list(f = "json")
  )
  expect_equal(sf::st_crs(res)$epsg, 28992L)
})

test_that("pdok_perform turns a 404 into a cli error", {
  httr2::local_mocked_responses(
    list(httr2::response(404, url = "https://api.pdok.nl/x"))
  )
  expect_error(
    pdok_perform(pdok_request("https://api.pdok.nl/x")),
    "404|not found"
  )
})

test_that("pdok_perform turns a transport failure into a cli error", {
  httr2::local_mocked_responses(function(req) {
    rlang::abort("boom", class = "httr2_failure")
  })
  expect_error(
    pdok_perform(pdok_request("https://api.pdok.nl/x")),
    "reach PDOK"
  )
})

test_that("parse_features combines pages and relabels the CRS", {
  p1 <- make_fc(list(c(5, 52), c(5.1, 52.1)))
  p2 <- make_fc(list(c(5.2, 52.2)))
  out <- parse_features(c(p1, p2), content_crs = 28992L)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_equal(sf::st_crs(out)$epsg, 28992L)
})

test_that("parse_features returns a 0-row sf for empty input", {
  out <- parse_features(make_fc(list()))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
})
