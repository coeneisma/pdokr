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
  # BAG is an ogc/v2 dataset; it must be included (the version regex fix).
  expect_equal(pdok_search_datasets("bag")$id, "kadaster/bag")
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
