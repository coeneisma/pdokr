#' List PDOK datasets
#'
#' Returns the full table of contents of datasets offered through the 'PDOK'
#' OGC API Features platform. The list is fetched once from
#' \url{https://api.pdok.nl/index.json} and cached for the session; if the
#' service cannot be reached, a snapshot bundled with the package is used
#' instead.
#'
#' @param refresh If `TRUE`, ignore the session cache and fetch the current list
#'   from PDOK again.
#'
#' @return A [tibble][tibble::tibble] with one row per dataset and the columns
#'   `id` (the identifier passed to [pdok_list_layers()] and [pdok_read()]),
#'   `name`, `description`, `keywords` (a list-column of character vectors),
#'   `services`, `owner`, and `ogc_url`.
#' @seealso [pdok_search_datasets()] to filter this list.
#' @examples
#' \donttest{
#' pdok_list_datasets()
#' }
#' @export
pdok_list_datasets <- function(refresh = FALSE) {
  fetch_index(force = refresh)
}

#' Search PDOK datasets
#'
#' Filters the dataset registry from [pdok_list_datasets()] by a
#' case-insensitive partial match. The query is matched against each dataset's
#' identifier, name, description, and keywords.
#'
#' @param query A single non-empty string to search for, e.g. `"gemeente"`.
#' @param refresh If `TRUE`, ignore the session cache and fetch the current list
#'   from PDOK again.
#'
#' @return A [tibble][tibble::tibble] with the same columns as
#'   [pdok_list_datasets()], containing only the matching rows (zero rows when
#'   nothing matches).
#' @seealso [pdok_list_datasets()] for the full list.
#' @examples
#' \donttest{
#' pdok_search_datasets("gemeente")
#' }
#' @export
pdok_search_datasets <- function(query, refresh = FALSE) {
  if (!rlang::is_string(query) || !nzchar(query)) {
    cli::cli_abort("{.arg query} must be a single non-empty string.")
  }

  reg <- pdok_list_datasets(refresh = refresh)
  keywords <- vapply(
    reg$keywords,
    function(k) paste(k, collapse = " "),
    character(1)
  )
  haystack <- tolower(paste(reg$id, reg$name, reg$description, keywords))
  keep <- grepl(tolower(query), haystack, fixed = TRUE)
  reg[keep, , drop = FALSE]
}
