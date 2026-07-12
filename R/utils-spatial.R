# CRS and bounding-box helpers.
#
# These support pdok_read() (server-side bbox pre-filter and CRS handling) and
# the filter_by workflow. All internal; depend only on sf. PDOK's OGC API takes
# its `bbox` parameter in CRS84 (lon/lat) by default, so we normalise to that.

#' Normalise an input to a CRS84 bounding-box vector
#'
#' @param x A numeric vector `c(xmin, ymin, xmax, ymax)` (assumed CRS84), or an
#'   `sf`, `sfc`, or `bbox` object (whose extent is transformed to CRS84).
#' @param call Calling environment, for error messages.
#'
#' @return A named numeric vector `c(xmin, ymin, xmax, ymax)` in CRS84
#'   (lon/lat), suitable for the OGC `bbox` query parameter.
#' @noRd
# Internal: expand a zero-width or zero-height bbox by a small margin, so a
# point or line still yields a usable, non-empty OGC bbox query (a degenerate
# bbox is rejected by the server with HTTP 400).
pad_degenerate_bbox <- function(b, pad = 1e-3) {
  if (b[["xmax"]] - b[["xmin"]] == 0) {
    b[["xmin"]] <- b[["xmin"]] - pad
    b[["xmax"]] <- b[["xmax"]] + pad
  }
  if (b[["ymax"]] - b[["ymin"]] == 0) {
    b[["ymin"]] <- b[["ymin"]] - pad
    b[["ymax"]] <- b[["ymax"]] + pad
  }
  b
}

as_bbox_crs84 <- function(x, call = rlang::caller_env()) {
  # Bare numeric vector: assume it is already CRS84 and pass through.
  if (is.numeric(x) && !inherits(x, "bbox")) {
    if (length(x) != 4L || anyNA(x) || !all(is.finite(x))) {
      cli::cli_abort(
        "A numeric bbox must be four finite values: {.code c(xmin, ymin, xmax, ymax)}.",
        call = call
      )
    }
    if (x[1] > x[3] || x[2] > x[4]) {
      cli::cli_abort(
        "A numeric bbox must have {.code xmin <= xmax} and {.code ymin <= ymax}.",
        call = call
      )
    }
    out <- stats::setNames(as.numeric(x), c("xmin", "ymin", "xmax", "ymax"))
    return(pad_degenerate_bbox(out))
  }

  # CRS-aware objects: take the extent and transform to CRS84.
  if (inherits(x, c("sf", "sfc", "bbox"))) {
    bb <- sf::st_bbox(x)
    if (is.na(sf::st_crs(bb))) {
      cli::cli_abort(
        c(
          "Cannot transform the bounding box: its coordinate reference system is unknown.",
          "i" = "Set a CRS on the object (e.g. with {.fn sf::st_set_crs}) or pass a numeric CRS84 bbox."
        ),
        call = call
      )
    }

    poly <- sf::st_as_sfc(bb)
    if (!isTRUE(sf::st_is_longlat(bb))) {
      # Projected input: densify in (planar) map units so the reprojected box
      # fully covers the area. A slightly larger box is harmless; too small
      # would drop data. Segmentising geographic coordinates would need lwgeom,
      # which we avoid by only doing it for projected CRSs.
      span <- max(bb[["xmax"]] - bb[["xmin"]], bb[["ymax"]] - bb[["ymin"]])
      if (is.finite(span) && span > 0) {
        poly <- sf::st_segmentize(poly, dfMaxLength = span / 20)
      }
    }
    bb84 <- sf::st_bbox(sf::st_transform(poly, 4326))
    out <- stats::setNames(as.numeric(bb84), c("xmin", "ymin", "xmax", "ymax"))
    return(pad_degenerate_bbox(out))
  }

  cli::cli_abort(
    "A bounding box must be a numeric vector of length 4, or an {.cls sf}, {.cls sfc}, or {.cls bbox} object.",
    call = call
  )
}

#' Parse a Content-Crs response header into an EPSG code
#'
#' @param header The `Content-Crs` header value, e.g.
#'   `"<http://www.opengis.net/def/crs/EPSG/0/28992>"`, or the CRS84 URI.
#'
#' @return An integer EPSG code, or `NULL` when the header is missing or
#'   unrecognised. CRS84 maps to `4326`.
#' @noRd
parse_content_crs <- function(header) {
  if (is.null(header) || length(header) == 0L || !nzchar(header[[1]])) {
    return(NULL)
  }
  h <- gsub("[<>[:space:]]", "", header[[1]])
  if (grepl("CRS84", h, ignore.case = TRUE)) {
    return(4326L)
  }
  num <- sub(".*/", "", h)
  if (grepl("^[0-9]+$", num)) {
    return(as.integer(num))
  }
  NULL
}
