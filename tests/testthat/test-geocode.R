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

rev_body <- function() {
  paste0(
    '{"response":{"numFound":1,"docs":[',
    '{"id":"adr-1","type":"adres","weergavenaam":"Boterstraat 2A, 3511LZ Utrecht",',
    '"afstand":1.8,"geometrie_ll":"POINT(5.121 52.090)"}',
    ']}}'
  )
}

rev_resp <- function(body = rev_body()) {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/reverse",
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
  expect_warning(out <- pdok_geocode("zzz-nonexistent"), "No result")
  expect_equal(nrow(out), 0L)
})

test_that("pdok_geocode geocodes a vector and tags rows with query", {
  # each query returns the 2-doc body; the query column maps rows to inputs
  httr2::local_mocked_responses(function(req) ls_resp())
  out <- pdok_geocode(c("A", "B"))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 4L)
  expect_equal(names(out)[1], "query")
  expect_setequal(unique(out$query), c("A", "B"))
})

test_that("pdok_geocode warns about queries that match nothing", {
  empty <- ls_resp('{"response":{"numFound":0,"docs":[]}}')
  # first query returns nothing, second matches
  httr2::local_mocked_responses(list(empty, ls_resp()))
  expect_warning(out <- pdok_geocode(c("nope", "yes")), "No result for 1 of 2")
  expect_true(all(out$query == "yes"))
})

test_that("pdok_geocode validates its arguments", {
  expect_error(pdok_geocode(1), "character vector")
  expect_error(pdok_geocode(character(0)), "character vector")
  expect_error(pdok_geocode(c("a", NA)), "character vector")
  expect_error(pdok_geocode(c("a", "")), "character vector")
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

test_that("pdok_reverse_geocode returns nearest matches with distance", {
  httr2::local_mocked_responses(function(req) rev_resp())
  pts <- sf::st_sfc(
    sf::st_point(c(5.121, 52.090)), sf::st_point(c(5.13, 52.10)), crs = 4326
  )
  out <- pdok_reverse_geocode(pts)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)                 # one match per point
  expect_equal(names(out)[1], "point_id")
  expect_setequal(out$point_id, c(1L, 2L))
  expect_type(out$afstand, "double")          # distance stays numeric
})

test_that("pdok_reverse_geocode queries in lon/lat and honours crs", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req$url
    rev_resp()
  })
  # an RD point must still be queried as lon/lat
  pt_rd <- sf::st_sfc(sf::st_point(c(136000, 456000)), crs = 28992)
  out <- pdok_reverse_geocode(pt_rd, crs = 28992)
  expect_match(seen, "lon=")
  expect_match(seen, "lat=")
  expect_equal(sf::st_crs(out)$epsg, 28992L)
})

test_that("pdok_reverse_geocode validates its input", {
  expect_error(pdok_reverse_geocode("nope"), "must be an")
  no_crs <- sf::st_sfc(sf::st_point(c(5, 52)))
  expect_error(pdok_reverse_geocode(no_crs), "coordinate reference system")
  poly <- sf::st_sfc(
    sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 0)))), crs = 4326
  )
  expect_error(pdok_reverse_geocode(poly), "POINT")
  pt <- sf::st_sfc(sf::st_point(c(5, 52)), crs = 4326)
  expect_error(pdok_reverse_geocode(pt, limit = 0), "positive whole number")
  expect_error(pdok_reverse_geocode(pt, crs = "RD"), "EPSG code")
  expect_error(pdok_reverse_geocode(pt, type = "stad"), "must be one of")
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

test_that("pdok_reverse_geocode works against the live Locatieserver", {
  skip_on_cran()
  skip_if_offline()
  pt <- sf::st_sfc(sf::st_point(c(5.121, 52.090)), crs = 4326)
  out <- pdok_reverse_geocode(pt)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 1L)
  expect_true(is.numeric(out$afstand) && out$afstand >= 0)
})
