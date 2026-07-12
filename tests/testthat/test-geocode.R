ls_body <- function() {
  paste0(
    '{"response":{"numFound":2,"docs":[',
    '{"id":"adr-1","type":"adres","weergavenaam":"Park Arenberg 88, De Bilt",',
    '"gemeentenaam":"De Bilt","woonplaatsnaam":"De Bilt","score":9.5,',
    '"geometrie_ll":"POINT(5.171 52.106)","centroide_ll":"POINT(5.171 52.106)"},',
    '{"id":"gem-1","type":"gemeente","weergavenaam":"Gemeente De Bilt",',
    '"gemeentenaam":"De Bilt","score":8.0,',
    '"geometrie_ll":"MULTIPOLYGON(((5.1 52.0,5.3 52.0,5.3 52.2,5.1 52.2,5.1 52.0)))",',
    '"centroide_ll":"POINT(5.2 52.1)"}',
    ']}}'
  )
}

ls_resp <- function(body = ls_body()) {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(body)
  )
}

test_that("parse_locatieserver returns all fields as an sf", {
  docs <- httr2::resp_body_json(ls_resp())$response$docs
  out <- parse_locatieserver(docs)

  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)
  # Most useful fields first; geometry text fields dropped.
  expect_equal(names(out)[1:4], c("weergavenaam", "type", "score", "gemeentenaam"))
  expect_false("geometrie_ll" %in% names(out))
  # score stays numeric; other fields are kept too.
  expect_type(out$score, "double")
  expect_equal(out$score, c(9.5, 8.0))
  expect_true("woonplaatsnaam" %in% names(out))
  # Point for the address, polygon for the municipality.
  expect_equal(
    as.character(sf::st_geometry_type(out)),
    c("POINT", "MULTIPOLYGON")
  )
  expect_equal(sf::st_crs(out)$epsg, 4326L)
})

test_that("parse_locatieserver drops a result without geometry", {
  docs <- list(
    list(id = "a", type = "adres", weergavenaam = "A",
         geometrie_ll = "POINT(5 52)"),
    list(id = "b", type = "adres", weergavenaam = "B") # no geometry at all
  )
  res <- parse_locatieserver(docs)
  expect_s3_class(res, "sf")
  expect_equal(nrow(res), 1L)
  expect_equal(res$weergavenaam, "A")
})

test_that("parse_locatieserver collapses a multi-value field", {
  # Locatieserver returns some fields as arrays; they must become one string,
  # not a list-column or an error.
  docs <- list(
    list(id = "a", type = "adres", weergavenaam = "A",
         geometrie_ll = "POINT(5 52)", suggest = list("Foo", "Bar"))
  )
  res <- parse_locatieserver(docs)
  expect_equal(nrow(res), 1L)
  expect_type(res$suggest, "character")
  expect_equal(res$suggest, "Foo; Bar")
})

test_that("pdok_geocode returns an sf and transforms crs", {
  httr2::local_mocked_responses(list(ls_resp()))
  out <- pdok_geocode("De Bilt")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)

  httr2::local_mocked_responses(list(ls_resp()))
  out_rd <- pdok_geocode("De Bilt", crs = 28992)
  expect_equal(sf::st_crs(out_rd)$epsg, 28992L)
})

test_that("pdok_geocode warns and returns 0 rows for no matches", {
  httr2::local_mocked_responses(list(ls_resp('{"response":{"numFound":0,"docs":[]}}')))
  expect_warning(out <- pdok_geocode("zzz-nonexistent"), "No results")
  expect_equal(nrow(out), 0L)
})

test_that("pdok_geocode validates its arguments", {
  expect_error(pdok_geocode(1), "single non-empty string")
  expect_error(pdok_geocode(""), "single non-empty string")
  expect_error(pdok_geocode("x", limit = 0), "positive whole number")
  expect_error(pdok_geocode("x", limit = 1.5), "positive whole number")
  expect_error(pdok_geocode("x", type = "stad"), "must be one of")
  expect_error(pdok_geocode("x", crs = "RD"), "EPSG code")
})

test_that("pdok_geocode maps type and limit into the query", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req$url
    ls_resp()
  })
  pdok_geocode("Utrecht", type = "gemeente", limit = 5)
  expect_match(seen, "fq=type%3Agemeente")
  expect_match(seen, "rows=5")
})

test_that("pdok_geocode works against the live Locatieserver", {
  skip_on_cran()
  skip_if_offline()
  pt <- pdok_geocode("Park Arenberg 88, De Bilt")
  expect_s3_class(pt, "sf")
  expect_equal(as.character(sf::st_geometry_type(pt))[1], "POINT")

  gem <- pdok_geocode("De Bilt", type = "gemeente")
  expect_true(grepl("POLYGON", as.character(sf::st_geometry_type(gem))[1]))
})
