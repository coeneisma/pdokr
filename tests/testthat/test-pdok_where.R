test_that("pdok_where translates comparisons and logic to CQL2", {
  expect_equal(as.character(pdok_where(postcode == "3811MZ")), "postcode = '3811MZ'")
  expect_equal(as.character(pdok_where(huisnummer != 1)), "huisnummer <> 1")
  expect_equal(as.character(pdok_where(huisnummer >= 10)), "huisnummer >= 10")
  expect_equal(
    as.character(pdok_where(woonplaats_naam == "Amersfoort" & huisnummer < 5)),
    "woonplaats_naam = 'Amersfoort' AND huisnummer < 5"
  )
  expect_equal(
    as.character(pdok_where(postcode == "3811MZ" | postcode == "3811MS")),
    "postcode = '3811MZ' OR postcode = '3811MS'"
  )
})

test_that("pdok_where parenthesizes OR inside AND", {
  out <- as.character(pdok_where(
    (postcode == "a" | postcode == "b") & huisnummer == 1
  ))
  expect_equal(out, "(postcode = 'a' OR postcode = 'b') AND huisnummer = 1")
})

test_that("pdok_where translates %in%, like, between, is.na and NOT", {
  expect_equal(
    as.character(pdok_where(postcode %in% c("3811MZ", "3811MS"))),
    "postcode IN ('3811MZ', '3811MS')"
  )
  expect_equal(
    as.character(pdok_where(like(openbare_ruimte_naam, "Lange%"))),
    "openbare_ruimte_naam LIKE 'Lange%'"
  )
  expect_equal(
    as.character(pdok_where(between(huisnummer, 1, 9))),
    "huisnummer BETWEEN 1 AND 9"
  )
  expect_equal(as.character(pdok_where(is.na(huisletter))), "huisletter IS NULL")
  expect_equal(as.character(pdok_where(!is.na(huisletter))), "huisletter IS NOT NULL")
  expect_equal(
    as.character(pdok_where(!(postcode == "x"))),
    "NOT (postcode = 'x')"
  )
})

test_that("pdok_where applies casei/accenti to both sides", {
  expect_equal(
    as.character(pdok_where(casei(woonplaats_naam) == "AMERSFOORT")),
    "casei(woonplaats_naam) = casei('AMERSFOORT')"
  )
  expect_equal(
    as.character(pdok_where(like(casei(openbare_ruimte_naam), "lange%"))),
    "casei(openbare_ruimte_naam) LIKE casei('lange%')"
  )
  expect_equal(
    as.character(pdok_where(accenti(woonplaats_naam) == "Belgie")),
    "accenti(woonplaats_naam) = accenti('Belgie')"
  )
})

test_that("pdok_where escapes quotes and renders types", {
  expect_equal(
    as.character(pdok_where(woonplaats_naam == "'s-Gravenhage")),
    "woonplaats_naam = '''s-Gravenhage'"
  )
  expect_equal(as.character(pdok_where(actief == TRUE)), "actief = true")
  expect_equal(
    as.character(pdok_where(peildatum == as.Date("2024-01-31"))),
    "peildatum = DATE('2024-01-31')"
  )
  # large numbers must not become scientific notation
  expect_equal(
    as.character(pdok_where(oppervlakte > 1e6)),
    "oppervlakte > 1000000"
  )
})

test_that("pdok_where evaluates values in the caller's environment", {
  pc <- "3811MZ"
  codes <- c("a", "b")
  expect_equal(as.character(pdok_where(postcode == pc)), "postcode = '3811MZ'")
  expect_equal(
    as.character(pdok_where(postcode %in% codes)),
    "postcode IN ('a', 'b')"
  )
  expect_equal(as.character(pdok_where(huisnummer == 1 + 1)), "huisnummer = 2")
})

test_that("pdok_where rejects invalid input clearly", {
  expect_error(pdok_where(), "filter expression")
  expect_error(pdok_where(postcode == c("a", "b")), "single non-missing")
  expect_error(pdok_where(postcode == NA), "single non-missing")
  expect_error(pdok_where(postcode %in% character()), "non-empty vector")
  ids <- c("a", NA, NA)
  expect_error(pdok_where(postcode %in% ids), "2 missing values")
  expect_error(pdok_where(postcode %in% ids), "ids\\[!is.na\\(ids\\)\\]")
  expect_error(pdok_where(postcode %in% c("a", NA)), "1 missing value")
  expect_error(pdok_where(toupper(postcode) == "X"), "left-hand side")
  expect_error(pdok_where(grepl("x", postcode)), "Unsupported function")
  expect_error(pdok_where(TRUE), "Unsupported filter expression")
  expect_error(pdok_where(casei(postcode) %in% c("a", "b")), "not supported")
})

test_that("a long %in% renders one filter string per batch", {
  ids <- sprintf("id%04d", seq_len(650))
  w <- pdok_where(identificatie %in% ids & status == "ok")
  qs <- as.character(w)
  expect_length(qs, 3L) # 300 + 300 + 50
  expect_match(qs, "^identificatie IN \\(", all = TRUE)
  expect_match(qs, "AND status = 'ok'$", all = TRUE)
  # every id appears exactly once across the batches
  got <- unlist(regmatches(qs, gregexpr("id\\d{4}", qs)))
  expect_setequal(got, ids)
  expect_equal(length(got), length(ids))
})

test_that("a long %in% deduplicates values before batching", {
  ids <- rep(sprintf("id%04d", seq_len(200)), 3) # 600 values, 200 unique
  w <- pdok_where(identificatie %in% ids)
  expect_length(as.character(w), 1L)
})

test_that("a long %in% is refused inside | or !, and at most once", {
  ids <- sprintf("id%04d", seq_len(400))
  expect_error(
    pdok_where(identificatie %in% ids | status == "ok"),
    "cannot be used inside"
  )
  expect_error(
    pdok_where(!(identificatie %in% ids)),
    "cannot be used inside"
  )
  expect_error(
    pdok_where(identificatie %in% ids & nummer %in% ids),
    "Only one"
  )
})

test_that("print method shows the filter and batching", {
  expect_output(print(pdok_where(postcode == "x")), "postcode = 'x'", fixed = TRUE)
  ids <- sprintf("id%04d", seq_len(400))
  expect_output(print(pdok_where(identificatie %in% ids)), "more batched request")
})

test_that("has() translates to a contains-LIKE with escaped wildcards", {
  expect_equal(
    as.character(pdok_where(has(gebruiksdoel, "onderwijsfunctie"))),
    "gebruiksdoel LIKE '%onderwijsfunctie%'"
  )
  # wildcards and backslashes in the value are matched literally
  expect_equal(
    as.character(pdok_where(has(naam, "50%_korting\\"))),
    "naam LIKE '%50\\%\\_korting\\\\%'"
  )
  # casei() wraps both sides, like elsewhere
  expect_equal(
    as.character(pdok_where(has(casei(gebruiksdoel), "Onderwijsfunctie"))),
    "casei(gebruiksdoel) LIKE casei('%Onderwijsfunctie%')"
  )
  # values come from the caller's environment
  doel <- "sportfunctie"
  expect_equal(
    as.character(pdok_where(has(gebruiksdoel, doel))),
    "gebruiksdoel LIKE '%sportfunctie%'"
  )
})

test_that("has() rejects a non-string value", {
  expect_error(pdok_where(has(gebruiksdoel, 1)), "single non-empty string")
  expect_error(pdok_where(has(gebruiksdoel, "")), "single non-empty string")
  expect_error(
    pdok_where(has(gebruiksdoel, c("a", "b"))),
    "single non-empty string"
  )
})
