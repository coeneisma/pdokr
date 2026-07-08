test_that("resolve_dataset looks a registry id up in the index (any version)", {
  httr2::local_mocked_responses(function(req) mock_index_resp())

  res <- resolve_dataset("cbs/gebiedsindelingen")
  expect_equal(res$id, "cbs/gebiedsindelingen")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")

  # BAG is an ogc/v2 dataset; the resolved URL must use v2, not an assumed v1.
  res2 <- resolve_dataset("kadaster/bag")
  expect_equal(res2$ogc, "https://api.pdok.nl/kadaster/bag/ogc/v2")
})

test_that("resolve_dataset trims surrounding slashes from an id", {
  httr2::local_mocked_responses(function(req) mock_index_resp())
  res <- resolve_dataset("/cbs/gebiedsindelingen/")
  expect_equal(res$id, "cbs/gebiedsindelingen")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
})

test_that("resolve_dataset errors on an unknown registry id", {
  httr2::local_mocked_responses(function(req) mock_index_resp())
  expect_error(resolve_dataset("no/such-dataset"), "Unknown dataset")
})

test_that("resolve_dataset passes through a raw OGC URL", {
  res <- resolve_dataset("https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
})

test_that("resolve_dataset rejects a WFS URL", {
  expect_error(
    resolve_dataset("https://service.pdok.nl/lv/bag/wfs/v2_0"),
    "WFS"
  )
})

test_that("resolve_dataset rejects invalid input", {
  expect_error(resolve_dataset(123), "single non-empty string")
  expect_error(resolve_dataset(c("a", "b")), "single non-empty string")
  expect_error(resolve_dataset(""), "single non-empty string")
})

test_that("parse_index builds a registry from an index body", {
  parsed <- list(apis = list(
    list(
      title = "CBS Gebiedsindelingen (OGC API)",
      description = "Administrative boundaries.",
      keywords = list("gemeente", "provincie"),
      links = list(
        list(href = "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1",
             rel = "root")
      )
    ),
    list(
      title = "BAG (OGC API)",
      description = "Buildings and addresses.",
      keywords = list("bag"),
      links = list(
        # An ogc/v2 dataset must be included, not dropped.
        list(href = "https://api.pdok.nl/kadaster/bag/ogc/v2", rel = "root")
      )
    )
  ))

  reg <- parse_index(parsed)
  expect_s3_class(reg, "tbl_df")
  expect_setequal(
    names(reg),
    c("id", "name", "description", "keywords", "services", "owner", "ogc_url")
  )
  expect_equal(nrow(reg), 2L)
  expect_equal(reg$id, c("cbs/gebiedsindelingen", "kadaster/bag"))
  expect_equal(reg$owner, c("cbs", "kadaster"))
  expect_equal(reg$ogc_url, c(
    "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1",
    "https://api.pdok.nl/kadaster/bag/ogc/v2"
  ))
  expect_type(reg$keywords, "list")
  expect_equal(reg$keywords[[1]], c("gemeente", "provincie"))
})

test_that("parse_index skips entries without an OGC link", {
  parsed <- list(apis = list(
    list(
      title = "Some WMS only",
      links = list(list(href = "https://service.pdok.nl/foo/wms/v1", rel = "root"))
    )
  ))
  reg <- parse_index(parsed)
  expect_equal(nrow(reg), 0L)
  expect_s3_class(reg, "tbl_df")
})

test_that("parse_index returns an empty registry for an empty index", {
  reg <- parse_index(list(apis = list()))
  expect_equal(nrow(reg), 0L)
})

test_that("ogc_supports_features reads the conformance document", {
  httr2::local_mocked_responses(function(req) mock_conformance_resp(features = TRUE))
  expect_true(ogc_supports_features("https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1"))

  httr2::local_mocked_responses(function(req) mock_conformance_resp(features = FALSE))
  expect_false(ogc_supports_features("https://api.pdok.nl/kadaster/brt-achtergrondkaart/ogc/v1"))
})

test_that("ogc_supports_features returns NA when it cannot be determined", {
  httr2::local_mocked_responses(function(req) cli::cli_abort("unreachable"))
  expect_true(is.na(ogc_supports_features("https://api.pdok.nl/x/ogc/v1")))
})
