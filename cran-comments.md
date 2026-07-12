## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

* Local: Arch Linux, R 4.6.1

## Submission notes

* This is the first submission of pdokr.

* pdokr is a client for the Dutch national geodata platform PDOK
  (<https://www.pdok.nl/>). Some examples and tests query the live PDOK web
  services. All network-using examples are wrapped in `\donttest{}`, and the
  integration tests are guarded with `skip_on_cran()` and `skip_if_offline()`,
  so `R CMD check` runs without network access on CRAN.

* The package writes only to `tempdir()` in its examples and tests.
