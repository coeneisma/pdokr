mock_collections_body <- function() {
  paste0(
    '{"collections":[',
    '{"id":"gemeente_gegeneraliseerd","title":"Gemeente",',
    '"description":"Municipalities.",',
    '"crs":["http://www.opengis.net/def/crs/OGC/1.3/CRS84",',
    '"http://www.opengis.net/def/crs/EPSG/0/28992"],',
    '"storageCrs":"http://www.opengis.net/def/crs/EPSG/0/28992",',
    '"extent":{"spatial":{"bbox":[[3.3,50.7,7.2,53.5]],',
    '"crs":"http://www.opengis.net/def/crs/OGC/1.3/CRS84"},',
    '"temporal":{"interval":[["2016-01-01T00:00:00Z",null]]}}},',
    '{"id":"provincie_gegeneraliseerd","title":"Provincie",',
    '"description":"Provinces.",',
    '"crs":["http://www.opengis.net/def/crs/EPSG/0/28992"],',
    '"storageCrs":"http://www.opengis.net/def/crs/EPSG/0/28992",',
    '"extent":{"spatial":{"bbox":[[3.3,50.7,7.2,53.5]]},',
    '"temporal":{"interval":[["1995-01-01T00:00:00Z","2015-12-31T00:00:00Z"]]}}}',
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
    c("layer", "title", "description", "start_date", "end_date",
      "crs", "storage_crs", "bbox")
  )
  expect_equal(reg$layer, c("gemeente_gegeneraliseerd", "provincie_gegeneraliseerd"))
  expect_equal(reg$crs[[1]], c(4326L, 28992L))
  expect_equal(reg$storage_crs, c(28992L, 28992L))
  expect_named(reg$bbox[[1]], c("xmin", "ymin", "xmax", "ymax"))
  expect_equal(unname(reg$bbox[[1]]), c(3.3, 50.7, 7.2, 53.5))
  # Temporal extent: ongoing layer has NA end; closed interval has both dates.
  expect_s3_class(reg$start_date, "Date")
  expect_equal(reg$start_date, as.Date(c("2016-01-01", "1995-01-01")))
  expect_equal(reg$end_date, as.Date(c(NA, "2015-12-31")))
})

test_that("pdok_list_layers returns the layer tibble", {
  httr2::local_mocked_responses(
    mock_pdok_dispatcher(collections = mock_collections_resp())
  )

  layers <- pdok_list_layers("cbs/gebiedsindelingen")
  expect_s3_class(layers, "tbl_df")
  expect_true("gemeente_gegeneraliseerd" %in% layers$layer)
  # Each row echoes its dataset, so it works directly with pdok_read().
  expect_equal(names(layers)[1], "dataset")
  expect_true(all(layers$dataset == "cbs/gebiedsindelingen"))
})

test_that("pdok_search_layers filters case-insensitively", {
  httr2::local_mocked_responses(
    mock_pdok_dispatcher(collections = mock_collections_resp())
  )

  res <- pdok_search_layers("cbs/gebiedsindelingen", "provincie")
  expect_equal(res$layer, "provincie_gegeneraliseerd")
  expect_equal(nrow(pdok_search_layers("cbs/gebiedsindelingen", "GEMEENTE")), 1L)
  expect_equal(nrow(pdok_search_layers("cbs/gebiedsindelingen", "no-such-xyz")), 0L)
})

test_that("pdok_search_layers validates its query", {
  expect_error(pdok_search_layers("cbs/gebiedsindelingen", 1), "single non-empty string")
  expect_error(pdok_search_layers("cbs/gebiedsindelingen", ""), "single non-empty string")
})

test_that("pdok_list_layers rejects a WFS URL", {
  expect_error(
    pdok_list_layers("https://service.pdok.nl/lv/bag/wfs/v2_0"),
    "WFS"
  )
})
