test_that("parse_queryables returns one row per field", {
  parsed <- httr2::resp_body_json(queryables_resp())
  out <- parse_queryables(parsed)
  expect_s3_class(out, "tbl_df")
  expect_equal(out$queryable, c("geometry", "postcode", "huisnummer"))
  # the geometry field carries a format instead of a type
  expect_equal(out$type, c("geometry-point", "string", "string"))
  expect_true(is.na(out$description[[1]]))
})

test_that("parse_queryables handles an empty properties object", {
  out <- parse_queryables(list(properties = list()))
  expect_equal(nrow(out), 0L)
  expect_named(out, c("queryable", "type", "description"))
})

test_that("pdok_list_queryables fetches and parses the queryables", {
  httr2::local_mocked_responses(
    mock_pdok_dispatcher(queryables = queryables_resp())
  )
  out <- pdok_list_queryables("kadaster/bag", "adres")
  expect_equal(nrow(out), 3L)
  expect_true("postcode" %in% out$queryable)
})

test_that("pdok_list_queryables points to the layer id on a 404", {
  httr2::local_mocked_responses(
    mock_pdok_dispatcher(queryables = queryables_resp(status = 404, body = "{}"))
  )
  expect_error(
    pdok_list_queryables("kadaster/bag", "adres"),
    "Check the layer id"
  )
})

test_that("pdok_list_queryables validates layer", {
  expect_error(pdok_list_queryables("kadaster/bag", ""), "single non-empty string")
})
