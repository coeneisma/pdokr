## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* Local: Arch Linux, R 4.6.1
* GitHub Actions: macOS (R release), Windows (R release),
  Ubuntu (R devel, release and oldrel-1)
* win-builder: Windows, R-devel

## Submission notes

* This is a feature release (0.1.0 -> 0.2.0). It adds server-side
  attribute filtering (`pdok_where()`, the `filter` argument of
  `pdok_read()`, `pdok_list_queryables()`) and `pdok_read_href()` for
  following links between features. There are no breaking changes.

* pdokr is a client for the Dutch national geodata platform PDOK
  (<https://www.pdok.nl/>). Some examples and tests query the live PDOK web
  services. All network-using examples are wrapped in `\donttest{}` and
  guarded by a short reachability probe (`@examplesIf`), so they are skipped
  with no error when PDOK is unavailable or slow. The integration tests are
  guarded with `skip_on_cran()` and `skip_if_offline()`, so `R CMD check`
  runs without network access on CRAN.

* The package writes only to `tempdir()` in its examples and tests.

## Reverse dependencies

There are no reverse dependencies.
