mock_collections_body <- function() {
  paste0(
    '{"collections":[',
    '{"id":"gemeente_gegeneraliseerd","title":"Gemeente",',
    '"description":"Municipalities.",',
    '"crs":["http://www.opengis.net/def/crs/OGC/1.3/CRS84",',
    '"http://www.opengis.net/def/crs/EPSG/0/28992"],',
    '"storageCrs":"http://www.opengis.net/def/crs/EPSG/0/28992",',
    '"extent":{"spatial":{"bbox":[[3.3,50.7,7.2,53.5]],',
    '"crs":"http://www.opengis.net/def/crs/OGC/1.3/CRS84"}}},',
    '{"id":"provincie_gegeneraliseerd","title":"Provincie",',
    '"description":"Provinces.",',
    '"crs":["http://www.opengis.net/def/crs/EPSG/0/28992"],',
    '"storageCrs":"http://www.opengis.net/def/crs/EPSG/0/28992",',
    '"extent":{"spatial":{"bbox":[[3.3,50.7,7.2,53.5]]}}}',
    ']}'
  )
}

mock_collections_resp <- function() {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/collections",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(mock_collections_body())
  )
}

test_that("parse_collections builds a layer registry", {
  parsed <- httr2::resp_body_json(mock_collections_resp())
  reg <- parse_collections(parsed)

  expect_s3_class(reg, "tbl_df")
  expect_equal(nrow(reg), 2L)
  expect_setequal(
    names(reg),
    c("layer", "title", "description", "crs", "storage_crs", "bbox")
  )
  expect_equal(reg$layer, c("gemeente_gegeneraliseerd", "provincie_gegeneraliseerd"))
  expect_equal(reg$crs[[1]], c(4326L, 28992L))
  expect_equal(reg$storage_crs, c(28992L, 28992L))
  expect_named(reg$bbox[[1]], c("xmin", "ymin", "xmax", "ymax"))
  expect_equal(unname(reg$bbox[[1]]), c(3.3, 50.7, 7.2, 53.5))
})

test_that("pdok_list_layers returns and caches the layer tibble", {
  pdok_clear_cache()
  on.exit(pdok_clear_cache(), add = TRUE)

  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    if (n > 1L) cli::cli_abort("Network was hit a second time.")
    mock_collections_resp()
  })

  first <- pdok_list_layers("cbs/gebiedsindelingen")
  second <- pdok_list_layers("cbs/gebiedsindelingen")
  expect_equal(first, second)
  expect_equal(n, 1L)
  expect_true("gemeente_gegeneraliseerd" %in% first$layer)
})

test_that("pdok_search_layers filters case-insensitively", {
  pdok_clear_cache()
  on.exit(pdok_clear_cache(), add = TRUE)
  httr2::local_mocked_responses(function(req) mock_collections_resp())

  res <- pdok_search_layers("cbs/gebiedsindelingen", "provincie")
  expect_equal(res$layer, "provincie_gegeneraliseerd")
  expect_equal(nrow(pdok_search_layers("cbs/gebiedsindelingen", "GEMEENTE")), 1L)
  expect_equal(nrow(pdok_search_layers("cbs/gebiedsindelingen", "no-such-xyz")), 0L)
})

test_that("pdok_search_layers validates its query", {
  expect_error(pdok_search_layers("cbs/gebiedsindelingen", 1), "single non-empty string")
  expect_error(pdok_search_layers("cbs/gebiedsindelingen", ""), "single non-empty string")
})

test_that("pdok_list_layers rejects a WFS-only dataset", {
  expect_error(
    pdok_list_layers("https://service.pdok.nl/lv/bag/wfs/v2_0"),
    "no OGC API Features endpoint"
  )
})
