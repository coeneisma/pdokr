# pdok_read_href(): follow the feature links that some PDOK layers carry.
#
# GoKoala (PDOK's OGC API server) can relate features across layers of one
# dataset. Such a relation shows up as a property named `<layer>.href`
# holding the URL(s) of the related feature(s), e.g. `pand.href` on a BAG
# verblijfsobject. The linked feature ids are opaque, and the API offers no
# way to fetch several features by id in one call, so following links means
# one request per distinct link. The requests are small (a single feature
# each) and PDOK serves them from cache, but they are performed with bounded
# concurrency and a rate limit so a long list stays polite.
#
# By default the result is `x` with the linked features attached, one row
# per link, like a join; `keep = FALSE` gives the linked features alone.

# Internal: the name of the link column of `x` that `column` refers to.
# `column` may be the full name ("pand.href") or just the linked layer
# ("pand"); when `x` has exactly one link column it may be left out.
resolve_link_column <- function(x, column, call = rlang::caller_env()) {
  link_cols <- grep("\\.href$", names(x), value = TRUE)
  hint <- if (length(link_cols)) {
    "Link column{?s} in {.arg x}: {.val {link_cols}}."
  } else {
    "{.arg x} has no column ending in {.val .href}; not every layer links to other layers."
  }
  if (is.null(column)) {
    if (length(link_cols) == 1L) {
      return(link_cols)
    }
    cli::cli_abort(
      c("{.arg column} must name the link column of {.arg x}.", "i" = hint),
      call = call
    )
  }
  if (!rlang::is_string(column) || !nzchar(column)) {
    cli::cli_abort(
      c("{.arg column} must be a single column name.", "i" = hint),
      call = call
    )
  }
  if (column %in% names(x)) {
    return(column)
  }
  if (paste0(column, ".href") %in% names(x)) {
    return(paste0(column, ".href"))
  }
  cli::cli_abort(
    c(
      "{.arg x} has no column {.val {column}} or {.val {paste0(column, '.href')}}.",
      "i" = hint
    ),
    call = call
  )
}

# Internal: one character vector of links per row of `x`, with NA and empty
# strings dropped. A GeoJSON array property arrives as a list-column; a
# single-valued one may be plain character.
row_links <- function(links) {
  lapply(links, function(l) {
    l <- as.character(l)
    l[!is.na(l) & nzchar(l)]
  })
}

# Internal: validate that links are feature URLs.
check_hrefs <- function(hrefs, call = rlang::caller_env()) {
  bad <- hrefs[!grepl("^https?://", hrefs)]
  if (length(bad) > 0L) {
    cli::cli_abort(
      c(
        "Links must be feature URLs (http/https).",
        "x" = "Not a URL: {.val {bad[[1]]}}{if (length(bad) > 1) ' and others' else ''}."
      ),
      call = call
    )
  }
  invisible(hrefs)
}

# Internal: read every distinct link once; an sf with the link in `href`
# (first column), or NULL when no link returned a feature.
read_hrefs <- function(hrefs, max_active, rate, call = rlang::caller_env()) {
  # One request per link, all in one throttle pool: at most `rate` requests
  # per second on average, `max_active` at a time.
  reqs <- lapply(hrefs, function(h) {
    httr2::req_throttle(
      pdok_request(h, query = list(f = "json")),
      capacity = rate, fill_time_s = 1, realm = "pdokr_href"
    )
  })
  # Same look as the other progress bars in the package; httr2 passes the
  # list on to cli::cli_progress_bar() and fills in the total.
  progress <- if (show_progress()) {
    list(
      format = paste0(
        "{cli::pb_spin} Downloading linked PDOK features: ",
        "{cli::pb_current}/{cli::pb_total} | ETA {cli::pb_eta}"
      ),
      clear = TRUE
    )
  } else {
    FALSE
  }
  resps <- httr2::req_perform_parallel(
    reqs,
    on_error = "continue",
    progress = progress,
    max_active = max_active
  )

  ok <- vapply(resps, inherits, logical(1), "httr2_response")
  if (!all(ok)) {
    first <- resps[[which(!ok)[[1]]]]
    cli::cli_abort(
      c(
        "{sum(!ok)} of {length(hrefs)} linked feature{?s} could not be read.",
        "x" = "First failure: {conditionMessage(first)}",
        "i" = "URL: {.url {hrefs[[which(!ok)[[1]]]]}}"
      ),
      call = call
    )
  }

  content_crs <- parse_content_crs(httr2::resp_header(resps[[1]], "Content-Crs"))
  parts <- Map(
    function(resp, href) {
      feat <- parse_features(httr2::resp_body_string(resp), content_crs, call = call)
      if (nrow(feat) == 0L) {
        return(NULL)
      }
      feat$href <- href
      geom <- attr(feat, "sf_column")
      feat[, c("href", setdiff(names(feat), c("href", geom)), geom), drop = FALSE]
    },
    resps, hrefs
  )
  out <- rbind_sf(Filter(Negate(is.null), parts))
  if (!is.null(out)) {
    rownames(out) <- NULL
  }
  out
}

# Internal: attach the linked features to `x`, one row per link.
attach_hrefs <- function(x, col, keep, feats, call = rlang::caller_env()) {
  links <- row_links(x[[col]])
  n <- lengths(links)
  if (any(n == 0L)) {
    cli::cli_warn(
      "{sum(n == 0L)} row{?s} of {.arg x} ha{?s/ve} no link in {.val {col}} and {?is/are} dropped."
    )
  }
  idx <- rep(seq_along(links), n)
  href <- unlist(links, use.names = FALSE)
  m <- match(href, feats$href)
  if (anyNA(m)) {
    cli::cli_warn(
      "{sum(is.na(m))} link{?s} returned no feature; {?that row is/those rows are} dropped."
    )
    idx <- idx[!is.na(m)]
    href <- href[!is.na(m)]
    m <- m[!is.na(m)]
  }

  left <- if (inherits(x, "sf")) sf::st_drop_geometry(x) else x
  left <- as.data.frame(left)[idx, keep, drop = FALSE]
  left[[col]] <- href

  right <- feats[m, , drop = FALSE]
  geom <- attr(right, "sf_column")
  geometry <- sf::st_geometry(right)
  right <- sf::st_drop_geometry(right)
  right$href <- NULL
  # Both layers may carry e.g. `identificatie` and `status`: the linked
  # layer's copies get its name as prefix, matching the `<layer>.href` column.
  layer <- sub("\\.href$", "", col)
  clash <- names(right) %in% c(names(left), geom)
  names(right)[clash] <- paste0(layer, ".", names(right)[clash])
  names(right) <- make.unique(c(names(left), names(right)))[-seq_along(left)]

  out <- cbind(left, right)
  rownames(out) <- NULL
  out[[geom]] <- geometry
  sf::st_sf(out, sf_column_name = geom)
}

#' Read the features that a layer links to
#'
#' Some PDOK layers link each feature to related features in another layer
#' of the same dataset. In the BAG, for example, every `verblijfsobject`
#' (unit of use) carries a `pand.href` column with the URL of the building it
#' is part of, and every `pand` lists its units in `verblijfsobject.href`.
#' `pdok_read_href()` follows such links: it reads every linked feature and
#' attaches it to the row that links to it, so you get your own data with the
#' linked layer's columns and geometry alongside, like a join.
#'
#' This is the efficient way to get, say, the buildings behind a list of
#' addresses or units: each link is fetched directly, so nothing else is
#' downloaded. The link is the only key there is: a feature does not carry
#' the linked feature's own id (a `verblijfsobject` has no building
#' `identificatie`), and the id in the link is a server-internal one that
#' cannot be filtered on. When you do have the ids of the target layer
#' itself, a filter with [pdok_where()] (`identificatie %in% ids`) is the
#' faster route, as it fetches hundreds of features per request.
#'
#' Following links takes one request per distinct link. The requests are
#' small and are sent with bounded concurrency and a rate limit
#' (`max_active`, `rate`) so that a long list stays well within what PDOK
#' can comfortably serve; a few thousand links take about a minute.
#'
#' @param x An [sf][sf::st_sf] object or data frame holding a link column
#'   (typically read with [pdok_read()]), or a character vector of feature
#'   URLs.
#' @param column The link column of `x`: its name (e.g. `"pand.href"`), or
#'   just the layer it links to (`"pand"`, resolved to `"pand.href"`). May be
#'   left out when `x` has a single link column or is a character vector.
#' @param keep Which columns of `x` to return alongside the linked features:
#'   `TRUE` (the default) for all of them, a character vector of column
#'   names for a selection, or `FALSE` for none, which returns just the
#'   linked features, one row per distinct link. Ignored when `x` is a
#'   character vector.
#' @param crs Optional output CRS as an EPSG code (e.g. `28992` for RD New).
#'   `NULL` keeps the source CRS.
#' @param max_active Maximum number of requests in flight at the same time.
#' @param rate Maximum average number of requests per second.
#'
#' @return An [sf][sf::st_sf] object. By default it has one row per link: the
#'   kept columns of `x` (its own geometry is dropped and the link column now
#'   holds a single URL per row), then the linked feature's columns, then the
#'   linked feature's geometry. A row of `x` with several links becomes
#'   several rows; a row without links is dropped, with a warning. Columns of
#'   the linked layer whose name also occurs in `x` get the layer's name as a
#'   prefix (`pand.identificatie`, `pand.status`) so nothing is overwritten.
#'
#'   With `keep = FALSE`, or a character vector as `x`, the result has one
#'   row per distinct link, with the link as the first column, `href`.
#' @seealso [pdok_read()] to read a layer, whose result may carry link
#'   columns.
#' @examplesIf pdokr:::pdok_reachable("kadaster/bag/ogc/v2/collections/adres/items?limit=1&filter=postcode='3811MZ'")
#' \donttest{
#' # The units of use at one postal code, with the building each one is in
#' units <- pdok_read(
#'   "kadaster/bag", "verblijfsobject",
#'   filter = pdok_where(postcode == "3811MZ")
#' )
#' with_buildings <- pdok_read_href(units, "pand")
#' with_buildings[, c("identificatie", "pand.identificatie", "bouwjaar")]
#'
#' # Just the distinct buildings
#' buildings <- pdok_read_href(units, "pand", keep = FALSE)
#' nrow(buildings)
#' }
#' @export
pdok_read_href <- function(x, column = NULL, keep = TRUE, crs = NULL,
                           max_active = 4, rate = 10) {
  check_count(max_active, "max_active")
  if (!is.numeric(rate) || length(rate) != 1L || is.na(rate) || rate <= 0) {
    cli::cli_abort("{.arg rate} must be a single positive number (requests per second).")
  }
  if (!is.null(crs)) {
    check_crs(crs)
  }

  attach <- FALSE
  if (is.character(x)) {
    links <- row_links(list(x))
  } else if (is.data.frame(x)) {
    col <- resolve_link_column(x, column)
    links <- row_links(x[[col]])
    if (isTRUE(keep)) {
      attach <- TRUE
      keep <- setdiff(names(x), attr(x, "sf_column"))
    } else if (is.character(keep)) {
      attach <- TRUE
      missing <- setdiff(keep, names(x))
      if (length(missing) > 0L) {
        cli::cli_abort("{.arg keep} names column{?s} not in {.arg x}: {.val {missing}}.")
      }
      keep <- unique(c(keep, col))
    } else if (!isFALSE(keep)) {
      cli::cli_abort("{.arg keep} must be {.code TRUE}, {.code FALSE} or a character vector of column names.")
    }
  } else {
    cli::cli_abort(
      "{.arg x} must be an {.cls sf} or data frame with a link column, or a character vector of feature URLs."
    )
  }

  hrefs <- unique(unlist(links, use.names = FALSE))
  check_hrefs(hrefs)
  if (length(hrefs) == 0L) {
    cli::cli_warn("{.arg x} holds no links; nothing to read.")
    return(sf::st_sf(geometry = sf::st_sfc(crs = NA_integer_)))
  }

  feats <- read_hrefs(hrefs, max_active = max_active, rate = rate)
  if (is.null(feats)) {
    cli::cli_warn("None of the links returned a feature.")
    return(sf::st_sf(geometry = sf::st_sfc(crs = NA_integer_)))
  }

  out <- if (attach) attach_hrefs(x, col, keep, feats) else feats
  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  out
}
