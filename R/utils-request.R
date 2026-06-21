# HTTP layer: request construction, error handling, cursor pagination, and
# GeoJSON -> sf assembly. All internal; built on httr2 and sf.

#' Build a standard pdokr httr2 request
#'
#' @param url The endpoint URL.
#' @param query An optional named list of query parameters; `NULL` values are
#'   dropped.
#'
#' @return An unperformed `httr2_request`.
#' @noRd
pdok_request <- function(url, query = NULL) {
  req <- httr2::request(url)
  req <- httr2::req_user_agent(
    req, "pdokr (https://github.com/coeneisma/pdokr)"
  )
  req <- httr2::req_timeout(req, 60)
  req <- httr2::req_retry(req, max_tries = 3)

  query <- Filter(Negate(is.null), query %||% list())
  if (length(query) > 0L) {
    req <- httr2::req_url_query(req, !!!query)
  }
  req
}

#' Perform a request, turning HTTP and transport failures into cli errors
#'
#' @param req An `httr2_request`.
#' @param call Calling environment, for error messages.
#'
#' @return An `httr2_response` on success.
#' @noRd
pdok_perform <- function(req, call = rlang::caller_env()) {
  tryCatch(
    httr2::req_perform(req),
    httr2_http = function(cnd) {
      status <- httr2::resp_status(cnd$resp)
      url <- cnd$request$url %||% req$url
      if (status == 404L) {
        cli::cli_abort(
          c(
            "PDOK request failed: resource not found (HTTP 404).",
            "i" = "Check the dataset or layer id from {.fn pdok_search_datasets} / {.fn pdok_list_layers}.",
            "i" = "URL: {.url {url}}"
          ),
          call = call
        )
      }
      cli::cli_abort(
        c(
          "PDOK request failed (HTTP {status}).",
          "i" = "URL: {.url {url}}"
        ),
        call = call
      )
    },
    httr2_failure = function(cnd) {
      cli::cli_abort(
        c(
          "Could not reach PDOK.",
          "i" = "Check your internet connection; the service may be temporarily unavailable."
        ),
        call = call,
        parent = cnd
      )
    }
  )
}

#' Follow OGC API Features cursor pagination
#'
#' Performs the initial request and follows `rel = "next"` links until the
#' server stops offering one or `max_features` is reached.
#'
#' @param url The items endpoint URL.
#' @param query Query parameters for the first request (the `next` links carry
#'   their own parameters).
#' @param max_features Stop once at least this many features have been
#'   collected; `NULL` for all.
#' @param call Calling environment, for error messages.
#'
#' @return A list with `pages` (a character vector of raw GeoJSON page bodies),
#'   `content_crs` (the EPSG code from the first `Content-Crs` header, or
#'   `NULL`), and `n_features` (the number of features collected).
#' @noRd
paginate_ogc <- function(url, query = NULL, max_features = NULL,
                         call = rlang::caller_env()) {
  pages <- character(0)
  n_features <- 0L
  content_crs <- NULL
  next_url <- url
  next_query <- query

  repeat {
    resp <- pdok_perform(pdok_request(next_url, query = next_query), call = call)

    if (is.null(content_crs)) {
      content_crs <- parse_content_crs(httr2::resp_header(resp, "Content-Crs"))
    }

    parsed <- httr2::resp_body_json(resp)
    pages <- c(pages, httr2::resp_body_string(resp))
    n_features <- n_features + length(parsed$features %||% list())

    next_href <- NULL
    for (lnk in parsed$links %||% list()) {
      if (identical(lnk$rel, "next")) {
        next_href <- lnk$href
        break
      }
    }

    if (!is.null(max_features) && n_features >= max_features) break
    if (is.null(next_href)) break

    next_url <- next_href
    next_query <- NULL
  }

  list(pages = pages, content_crs = content_crs, n_features = n_features)
}

#' Combine GeoJSON page bodies into a single sf object
#'
#' @param pages A character vector of GeoJSON FeatureCollection bodies.
#' @param content_crs Optional EPSG code to assign (relabel) on the result,
#'   matching the server's `Content-Crs`.
#' @param call Calling environment, for error messages.
#'
#' @return An `sf` object (0 rows when no features were returned).
#' @noRd
parse_features <- function(pages, content_crs = NULL, call = rlang::caller_env()) {
  sfs <- lapply(pages, function(txt) {
    tryCatch(sf::read_sf(txt), error = function(e) NULL)
  })
  sfs <- Filter(function(s) !is.null(s) && nrow(s) > 0L, sfs)

  if (length(sfs) == 0L) {
    return(sf::st_sf(geometry = sf::st_sfc()))
  }

  out <- if (length(sfs) == 1L) sfs[[1]] else do.call(rbind, sfs)

  if (!is.null(content_crs)) {
    # Relabel, not reproject: PDOK already returns coordinates in this CRS,
    # but GeoJSON nominally implies CRS84, so we correct the label.
    out <- suppressWarnings(sf::st_set_crs(out, content_crs))
  }
  out
}
