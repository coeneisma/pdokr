# HTTP layer: request construction, error handling, cursor pagination, and
# GeoJSON -> sf assembly. All internal; built on httr2 and sf.

# Internal: rbind a list of sf objects that may have different attribute
# columns. GeoJSON can omit a null-valued property, so `sf::read_sf()` drops a
# column that is null for every feature on a page; two pages of the same layer
# can then carry different columns and a plain `rbind()` would abort with
# "names do not match previous names". We take the union of columns, fill the
# missing ones with NA, and align the order so the bind always succeeds.
rbind_sf <- function(parts) {
  if (length(parts) == 0L) {
    return(NULL)
  }
  if (length(parts) == 1L) {
    return(parts[[1]])
  }
  all_cols <- unique(unlist(lapply(parts, names)))
  aligned <- lapply(parts, function(p) {
    for (m in setdiff(all_cols, names(p))) {
      p[[m]] <- NA
    }
    p[, all_cols, drop = FALSE]
  })
  do.call(rbind, aligned)
}

# Internal: show progress bars? Only in an interactive session, so they stay
# out of knitted documents and logs. All progress indicators in the package
# go through this one switch.
show_progress <- function() {
  rlang::is_interactive()
}

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
  # Retry transient server errors too (PDOK, e.g. BAG, occasionally returns a
  # 500/502/504 under load); httr2's default only retries 429/503.
  req <- httr2::req_retry(
    req,
    max_tries = 3,
    is_transient = function(resp) {
      httr2::resp_status(resp) %in% c(429L, 500L, 502L, 503L, 504L)
    }
  )

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
      # PDOK's JSON error bodies carry the useful explanation (e.g. a CQL2
      # parse error, or a filter on a field that is not queryable) in
      # `detail`; surface it instead of only the status code.
      detail <- tryCatch(
        {
          d <- httr2::resp_body_json(cnd$resp)$detail
          if (rlang::is_string(d) && nzchar(d)) gsub("[\r\n]+", " ", d) else NULL
        },
        error = function(e) NULL
      )
      detail_bullet <- if (!is.null(detail)) c("x" = "Server message: {detail}")
      # Each layer allows filtering on a selected set of fields only; point
      # to where that set can be found.
      if (!is.null(detail) && grepl("not a queryable property", detail, fixed = TRUE)) {
        detail_bullet <- c(
          detail_bullet,
          "i" = "See {.fn pdok_list_queryables} for the fields this layer can be filtered on."
        )
      }
      if (status == 404L) {
        cli::cli_abort(
          c(
            "PDOK request failed: resource not found (HTTP 404).",
            detail_bullet,
            "i" = "Check the dataset or layer id from {.fn pdok_search_datasets} / {.fn pdok_list_layers}.",
            "i" = "URL: {.url {url}}"
          ),
          call = call,
          class = "pdokr_http_error",
          status = status
        )
      }
      cli::cli_abort(
        c(
          "PDOK request failed (HTTP {status}).",
          detail_bullet,
          "i" = "URL: {.url {url}}"
        ),
        call = call,
        class = "pdokr_http_error",
        status = status
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
#' @param progress Show a spinner with the running feature count? Off when
#'   the caller reports progress itself (batched filters).
#' @param call Calling environment, for error messages.
#'
#' @return An `sf` object with the (kept) features, trimmed to `max_features`.
#' @noRd
paginate_ogc <- function(url, query = NULL, max_features = NULL,
                         process = NULL, progress = TRUE,
                         call = rlang::caller_env()) {
  parts <- list()
  n_kept <- 0L
  content_crs <- NULL
  next_url <- url
  next_query <- query

  # Total is unknown (the API does not return numberMatched), so this is a
  # spinner that reports the running feature count.
  progress <- progress && show_progress()
  if (progress) {
    cli::cli_progress_bar(
      format = "{cli::pb_spin} Downloading PDOK features: {n_kept} fetched",
      clear = TRUE
    )
  }

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
    if (progress) cli::cli_progress_update()

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
  if (progress) cli::cli_progress_done()

  if (length(parts) == 0L) {
    return(sf::st_sf(geometry = sf::st_sfc(crs = content_crs %||% NA_integer_)))
  }
  out <- rbind_sf(parts)
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

  out <- rbind_sf(sfs)

  if (!is.null(content_crs)) {
    # Relabel, not reproject: PDOK already returns coordinates in this CRS,
    # but GeoJSON nominally implies CRS84, so we correct the label.
    out <- suppressWarnings(sf::st_set_crs(out, content_crs))
  }
  out
}

#' Can a PDOK resource be fetched quickly right now?
#'
#' A probe for the examples: the network-using examples are wrapped in
#' `@examplesIf pdokr:::pdok_reachable(...)`, so they are skipped, rather
#' than failing, when there is no internet connection, when PDOK is down,
#' or when the service is so slow that the example would run into a timeout.
#' That is what the CRAN policy on internet resources asks for. The probe
#' makes a single small request with a short timeout and never raises.
#'
#' @param path A path on `https://api.pdok.nl/` to probe, or a full URL. The
#'   default fetches the dataset index that every registry lookup needs. An
#'   example on a dataset that is prone to slowness (the BAG) probes a
#'   request of the same kind it is about to make.
#' @param timeout Seconds before the probe gives up and reports `FALSE`.
#'
#' @return `TRUE` when the resource answered with a 2xx or 3xx status within
#'   the timeout, `FALSE` otherwise.
#' @noRd
pdok_reachable <- function(path = "index.json", timeout = 5) {
  url <- if (grepl("^https?://", path)) path else paste0("https://api.pdok.nl/", path)
  req <- httr2::request(url)
  req <- httr2::req_user_agent(req, "pdokr (https://github.com/coeneisma/pdokr)")
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  !is.null(resp) && httr2::resp_status(resp) < 400L
}
