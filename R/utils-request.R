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

#' Follow OGC API Features cursor pagination, assembling an sf object
#'
#' Performs the initial request and follows `rel = "next"` links. Each page is
#' parsed to `sf` (and passed through `process`, if given) as it arrives, so
#' when `process` filters the data the loop stops as soon as `max_features`
#' *kept* features have been collected — not after `max_features` raw features.
#'
#' @param url The items endpoint URL.
#' @param query Query parameters for the first request (the `next` links carry
#'   their own parameters).
#' @param max_features Stop once at least this many (kept) features have been
#'   collected; `NULL` for all.
#' @param process Optional function applied to each page's `sf` (e.g. a spatial
#'   clip). Returns the features to keep from that page.
#' @param call Calling environment, for error messages.
#'
#' @return An `sf` object with the (kept) features, trimmed to `max_features`.
#' @noRd
paginate_ogc <- function(url, query = NULL, max_features = NULL,
                         process = NULL, call = rlang::caller_env()) {
  parts <- list()
  n_kept <- 0L
  content_crs <- NULL
  next_url <- url
  next_query <- query

  # Total is unknown (the API does not return numberMatched), so this is a
  # spinner that reports the running feature count. cli keeps it quiet in
  # non-interactive sessions.
  cli::cli_progress_bar(
    format = "{cli::pb_spin} Downloading PDOK features: {n_kept} fetched",
    clear = TRUE
  )

  repeat {
    resp <- pdok_perform(pdok_request(next_url, query = next_query), call = call)

    if (is.null(content_crs)) {
      content_crs <- parse_content_crs(httr2::resp_header(resp, "Content-Crs"))
    }

    parsed <- httr2::resp_body_json(resp)
    page <- parse_features(httr2::resp_body_string(resp), content_crs, call = call)
    if (!is.null(process) && nrow(page) > 0L) {
      page <- process(page)
    }
    if (nrow(page) > 0L) {
      parts[[length(parts) + 1L]] <- page
    }
    n_kept <- n_kept + nrow(page)
    cli::cli_progress_update()

    next_href <- NULL
    for (lnk in parsed$links %||% list()) {
      if (identical(lnk$rel, "next")) {
        next_href <- lnk$href
        break
      }
    }

    if (!is.null(max_features) && n_kept >= max_features) break
    if (is.null(next_href)) break

    next_url <- next_href
    next_query <- NULL
  }
  cli::cli_progress_done()

  if (length(parts) == 0L) {
    return(sf::st_sf(geometry = sf::st_sfc(crs = content_crs %||% NA_integer_)))
  }
  out <- if (length(parts) == 1L) parts[[1]] else do.call(rbind, parts)
  if (!is.null(max_features) && nrow(out) > max_features) {
    out <- out[seq_len(max_features), , drop = FALSE]
  }
  out
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
    return(sf::st_sf(geometry = sf::st_sfc(crs = content_crs %||% NA_integer_)))
  }

  out <- if (length(sfs) == 1L) sfs[[1]] else do.call(rbind, sfs)

  if (!is.null(content_crs)) {
    # Relabel, not reproject: PDOK already returns coordinates in this CRS,
    # but GeoJSON nominally implies CRS84, so we correct the label.
    out <- suppressWarnings(sf::st_set_crs(out, content_crs))
  }
  out
}
