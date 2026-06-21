test_that("resolve_dataset handles a registry id", {
  res <- resolve_dataset("cbs/gebiedsindelingen")
  expect_equal(res$id, "cbs/gebiedsindelingen")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
  expect_null(res$wfs)
  expect_equal(res$services, "ogc")
})

test_that("resolve_dataset trims surrounding slashes from an id", {
  res <- resolve_dataset("/cbs/gebiedsindelingen/")
  expect_equal(res$id, "cbs/gebiedsindelingen")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
})

test_that("resolve_dataset passes through a raw OGC URL", {
  res <- resolve_dataset("https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1/")
  expect_equal(res$ogc, "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
  expect_null(res$wfs)
  expect_equal(res$services, "ogc")
})

test_that("resolve_dataset detects a WFS URL", {
  res <- resolve_dataset("https://service.pdok.nl/lv/bag/wfs/v2_0")
  expect_equal(res$wfs, "https://service.pdok.nl/lv/bag/wfs/v2_0")
  expect_null(res$ogc)
  expect_equal(res$services, "wfs")
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
        list(href = "https://api.pdok.nl/lv/bag/ogc/v1", rel = "root")
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
  expect_equal(reg$id, c("cbs/gebiedsindelingen", "lv/bag"))
  expect_equal(reg$owner, c("cbs", "lv"))
  expect_equal(reg$ogc_url[1], "https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1")
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
