# Session cache for capability/collection lookups.
#
# In-memory only: a package-level environment, never written to disk. This is
# CRAN-compliant (no files outside tempdir()) and resets when the R session
# restarts. Persistent caching across sessions, if ever needed, would use
# tools::R_user_dir() with explicit user consent.

# Internal: the cache store. parent = emptyenv() so lookups never fall through
# to other environments.
.pdokr_cache <- new.env(parent = emptyenv())

# Internal: retrieve a cached value, or NULL when the key is absent.
cache_get <- function(key) {
  if (exists(key, envir = .pdokr_cache, inherits = FALSE)) {
    get(key, envir = .pdokr_cache, inherits = FALSE)
  } else {
    NULL
  }
}

# Internal: store a value under a key. Returns the value invisibly.
cache_set <- function(key, value) {
  assign(key, value, envir = .pdokr_cache)
  invisible(value)
}

# Internal: whether a key is present in the cache.
cache_has <- function(key) {
  exists(key, envir = .pdokr_cache, inherits = FALSE)
}

#' Clear the pdokr session cache
#'
#' `pdokr` caches lookups such as dataset and layer listings in memory for the
#' duration of the R session, to avoid repeated network requests. Call this
#' function to empty that cache, for example to force a fresh request after PDOK
#' has published new data within the same session.
#'
#' The cache lives only in memory and is automatically discarded when the R
#' session ends; nothing is written to disk.
#'
#' @return No return value, called for side effects. Invisibly returns `NULL`.
#' @examples
#' pdok_clear_cache()
#' @export
pdok_clear_cache <- function() {
  rm(
    list = ls(envir = .pdokr_cache, all.names = TRUE),
    envir = .pdokr_cache
  )
  cli::cli_inform("Cleared the {.pkg pdokr} session cache.")
  invisible(NULL)
}
