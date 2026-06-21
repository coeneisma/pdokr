test_that("cache_set and cache_get round-trip a value", {
  on.exit(pdok_clear_cache(), add = TRUE)

  cache_set("answer", 42L)
  expect_true(cache_has("answer"))
  expect_equal(cache_get("answer"), 42L)
})

test_that("cache_get returns NULL for an absent key", {
  on.exit(pdok_clear_cache(), add = TRUE)

  expect_null(cache_get("does-not-exist"))
  expect_false(cache_has("does-not-exist"))
})

test_that("cache_set returns the value invisibly", {
  on.exit(pdok_clear_cache(), add = TRUE)

  expect_invisible(cache_set("x", "value"))
  expect_equal(cache_get("x"), "value")
})

test_that("pdok_clear_cache empties the cache and returns NULL invisibly", {
  cache_set("a", 1)
  cache_set("b", 2)
  expect_true(cache_has("a"))

  expect_message(res <- pdok_clear_cache(), "Cleared")
  expect_null(res)
  expect_false(cache_has("a"))
  expect_false(cache_has("b"))
})
