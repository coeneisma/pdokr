mock_index_body <- function() {
  paste0(
    '{"apis":[',
    '{"title":"CBS Gebiedsindelingen","description":"Administrative boundaries.",',
    '"keywords":["gemeente","provincie"],',
    '"links":[{"rel":"root","href":"https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1"}]},',
    '{"title":"BAG","description":"Buildings and addresses.",',
    '"keywords":["bag","adres"],',
    '"links":[{"rel":"root","href":"https://api.pdok.nl/lv/bag/ogc/v1"}]}',
    ']}'
  )
}

mock_index_resp <- function() {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/index.json",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(mock_index_body())
  )
}

test_that("pdok_list_datasets returns the registry tibble", {
  httr2::local_mocked_responses(function(req) mock_index_resp())

  reg <- pdok_list_datasets()
  expect_s3_class(reg, "tbl_df")
  expect_equal(nrow(reg), 2L)
  expect_setequal(
    names(reg),
    c("id", "name", "description", "keywords", "services", "owner", "ogc_url")
  )
  expect_true("cbs/gebiedsindelingen" %in% reg$id)
})

test_that("pdok_search_datasets filters case-insensitively", {
  httr2::local_mocked_responses(function(req) mock_index_resp())

  expect_equal(pdok_search_datasets("gemeente")$id, "cbs/gebiedsindelingen")
  expect_equal(pdok_search_datasets("GEMEENTE")$id, "cbs/gebiedsindelingen")
  expect_equal(pdok_search_datasets("bag")$id, "lv/bag")
  expect_equal(nrow(pdok_search_datasets("no-such-thing-xyz")), 0L)
})

test_that("pdok_search_datasets validates its query", {
  expect_error(pdok_search_datasets(123), "single non-empty string")
  expect_error(pdok_search_datasets(""), "single non-empty string")
  expect_error(pdok_search_datasets(c("a", "b")), "single non-empty string")
})

test_that("pdok_list_datasets errors when PDOK is unreachable", {
  httr2::local_mocked_responses(function(req) {
    rlang::abort("service down", class = "httr2_failure")
  })
  expect_error(pdok_list_datasets(), "reach PDOK")
})
