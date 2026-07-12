# Shared input-validation helpers, so equivalent arguments across the exported
# functions fail the same way with parallel, argument-naming messages.

# Internal: a single positive whole number (optionally NULL). Used for
# `max_features` (allow_null = TRUE) and `limit` (allow_null = FALSE).
check_count <- function(x, arg, allow_null = FALSE, call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(NULL))
  }
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1 && x == round(x)
  if (!ok) {
    suffix <- if (allow_null) " or `NULL`" else ""
    cli::cli_abort(
      "{.arg {arg}} must be a single positive whole number{suffix}.",
      call = call
    )
  }
  invisible(as.integer(x))
}

# Internal: a single positive EPSG code. Validates a user-supplied output CRS
# up front, so a bad value never reaches sf::st_transform() as an opaque GDAL
# error that names neither pdokr nor the argument.
check_crs <- function(crs, call = rlang::caller_env()) {
  ok <- is.numeric(crs) && length(crs) == 1L && !is.na(crs) &&
    crs > 0 && crs == round(crs)
  if (!ok) {
    cli::cli_abort(
      "{.arg crs} must be a single positive EPSG code (a whole number).",
      call = call
    )
  }
  invisible(as.integer(crs))
}
