# pdok_where(): translate an R filter expression into a CQL2 text filter.
#
# The translation is a plain recursive walk over the captured expression.
# Left-hand sides are field names, right-hand sides are R values evaluated in
# the caller's environment, so `postcode == pc` uses the variable `pc`.
#
# One structural subtlety is batching. PDOK's infrastructure drops a request
# with an over-long URL without any HTTP response (measured limit ~33KB), so a
# `%in%` over thousands of ids cannot be sent as a single `IN (...)`. When a
# `%in%` vector exceeds `pdok_in_batch_size`, pdok_where() records that one
# site separately; `filter_queries()` then renders one complete filter string
# per batch of values, and `read_ogc()` performs a request per batch and
# unions the results. Batching is only sound when the `%in%` is combined with
# the rest of the expression by AND, which is why a long `%in%` inside `|` or
# `!` is refused.

# Internal: %in% vectors longer than this are split over multiple requests.
# 300 BAG-sized ids (~19 chars quoted) keep the URL around 6KB, far below the
# ~33KB at which PDOK drops the connection.
pdok_in_batch_size <- 300L

# Internal: render one R literal as a CQL2 literal.
cql_literal <- function(x, call = rlang::caller_env()) {
  if (length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      "Filter values must be single non-missing values (use {.code is.na(field)} for {.code IS NULL}).",
      call = call
    )
  }
  if (inherits(x, "Date")) {
    return(sprintf("DATE('%s')", format(x, "%Y-%m-%d")))
  }
  if (inherits(x, "POSIXt")) {
    return(sprintf(
      "TIMESTAMP('%s')",
      format(as.POSIXct(x), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ))
  }
  if (is.character(x)) {
    return(paste0("'", gsub("'", "''", x, fixed = TRUE), "'"))
  }
  if (is.logical(x)) {
    return(if (x) "true" else "false")
  }
  if (is.numeric(x)) {
    return(format(x, scientific = FALSE, trim = TRUE, digits = 15L))
  }
  cli::cli_abort(
    "Filter values must be character, numeric, logical, Date or POSIXt, not {.cls {class(x)[[1]]}}.",
    call = call
  )
}

# Internal: render the field side of a comparison: a bare name, optionally
# wrapped in casei() or accenti(). Returns list(text=, wrap=).
cql_field <- function(expr, call = rlang::caller_env()) {
  if (rlang::is_symbol(expr)) {
    return(list(text = as.character(expr), wrap = NULL))
  }
  if (rlang::is_call(expr, c("casei", "accenti")) && length(expr) == 2L &&
      rlang::is_symbol(expr[[2]])) {
    fn <- as.character(expr[[1]])
    return(list(
      text = sprintf("%s(%s)", fn, as.character(expr[[2]])),
      wrap = fn
    ))
  }
  cli::cli_abort(
    c(
      "The left-hand side of a filter comparison must be a field name.",
      "i" = "A bare name such as {.code postcode}, optionally wrapped as {.code casei(name)} or {.code accenti(name)}.",
      "i" = "See {.fn pdok_list_queryables} for the fields a dataset supports."
    ),
    call = call
  )
}

# Internal: evaluate the value side of a comparison in the caller's
# environment and render it, applying the field's casei()/accenti() wrapper so
# both sides of the comparison are transformed alike.
cql_value <- function(expr, env, wrap, call = rlang::caller_env()) {
  x <- rlang::eval_tidy(expr, env = env)
  lit <- cql_literal(x, call = call)
  if (is.null(wrap)) lit else sprintf("%s(%s)", wrap, lit)
}

# Internal: is this expression (ignoring parentheses) an OR call? Used to
# decide where CQL2 needs explicit parentheses (AND binds tighter than OR).
is_or_call <- function(expr) {
  while (rlang::is_call(expr, "(")) {
    expr <- expr[[2]]
  }
  rlang::is_call(expr, c("|", "||"))
}

# Internal: recursively render an R expression as CQL2 text.
#
# `and_ctx` tracks whether the current position is joined to the whole
# expression purely by ANDs (required for batching a long %in%). `state`, when
# given, records the single long-%in% site found during the initial
# validation render. `batch` replaces that site's values when re-rendering one
# batch.
cql_render <- function(expr, env, and_ctx, state = NULL, batch = NULL,
                       call = rlang::caller_env()) {
  if (!rlang::is_call(expr) || !rlang::is_symbol(expr[[1]])) {
    cli::cli_abort(
      c(
        "Unsupported filter expression: {.code {rlang::expr_deparse(expr)}}.",
        "i" = "See {.fn pdok_where} for the supported comparison and logical operators."
      ),
      call = call
    )
  }
  fn <- as.character(expr[[1]])

  if (fn == "(") {
    return(cql_render(expr[[2]], env, and_ctx, state, batch, call = call))
  }

  if (fn %in% c("&", "&&", "|", "||")) {
    is_and <- fn %in% c("&", "&&")
    child_ctx <- and_ctx && is_and
    lhs <- cql_render(expr[[2]], env, child_ctx, state, batch, call = call)
    rhs <- cql_render(expr[[3]], env, child_ctx, state, batch, call = call)
    if (is_and) {
      # AND binds tighter than OR in CQL2, so OR operands need parentheses.
      if (is_or_call(expr[[2]])) lhs <- paste0("(", lhs, ")")
      if (is_or_call(expr[[3]])) rhs <- paste0("(", rhs, ")")
    }
    return(paste(lhs, if (is_and) "AND" else "OR", rhs))
  }

  if (fn == "!") {
    inner <- expr[[2]]
    while (rlang::is_call(inner, "(")) inner <- inner[[2]]
    if (rlang::is_call(inner, "is.na") && length(inner) == 2L) {
      f <- cql_field(inner[[2]], call = call)
      return(paste(f$text, "IS NOT NULL"))
    }
    return(paste0(
      "NOT (", cql_render(inner, env, FALSE, state, batch, call = call), ")"
    ))
  }

  ops <- c("==" = "=", "!=" = "<>", "<" = "<", "<=" = "<=", ">" = ">", ">=" = ">=")
  if (fn %in% names(ops)) {
    f <- cql_field(expr[[2]], call = call)
    v <- cql_value(expr[[3]], env, f$wrap, call = call)
    return(paste(f$text, ops[[fn]], v))
  }

  if (fn == "%in%") {
    f <- cql_field(expr[[2]], call = call)
    if (!is.null(f$wrap)) {
      cli::cli_abort(
        "{.code casei()}/{.code accenti()} are not supported with {.code %in%}; use {.code ==} per value or pre-normalize the values.",
        call = call
      )
    }
    vals <- rlang::eval_tidy(expr[[3]], env = env)
    if (!is.atomic(vals) || length(vals) == 0L) {
      cli::cli_abort(
        "The right-hand side of {.code %in%} must be a non-empty vector.",
        call = call
      )
    }
    if (anyNA(vals)) {
      # A missing value has no server-side meaning, and silently dropping it
      # would hide a data-quality problem in the user's ids; say what to do.
      nm <- if (rlang::is_symbol(expr[[3]])) as.character(expr[[3]]) else NULL
      hint <- if (is.null(nm)) {
        "Drop them first with {.code !is.na()}."
      } else {
        "Drop them first, e.g. {.code {nm}[!is.na({nm})]}."
      }
      cli::cli_abort(
        c(
          "The right-hand side of {.code %in%} holds {sum(is.na(vals))} missing value{?s} ({.code NA}), which a server-side filter cannot match.",
          "i" = hint
        ),
        call = call
      )
    }
    vals <- unique(vals)
    if (length(vals) > pdok_in_batch_size) {
      if (!and_ctx) {
        cli::cli_abort(
          c(
            "A {.code %in%} over more than {pdok_in_batch_size} values cannot be used inside {.code |} or {.code !}.",
            "i" = "Long value lists are sent as multiple requests, which is only possible when the {.code %in%} is combined with the rest of the filter by {.code &}.",
            "i" = "Split the request yourself, or restructure the filter."
          ),
          call = call
        )
      }
      if (!is.null(state)) {
        if (state$found) {
          cli::cli_abort(
            "Only one {.code %in%} over more than {pdok_in_batch_size} values is supported per filter.",
            call = call
          )
        }
        state$found <- TRUE
        state$field <- f$text
        state$values <- vals
      }
      if (!is.null(batch)) {
        vals <- batch
      } else {
        vals <- vals[seq_len(pdok_in_batch_size)]
      }
    }
    lits <- vapply(vals, cql_literal, character(1), call = call)
    return(sprintf("%s IN (%s)", f$text, paste(lits, collapse = ", ")))
  }

  if (fn == "like" && length(expr) == 3L) {
    f <- cql_field(expr[[2]], call = call)
    v <- cql_value(expr[[3]], env, f$wrap, call = call)
    return(paste(f$text, "LIKE", v))
  }

  if (fn == "has" && length(expr) == 3L) {
    f <- cql_field(expr[[2]], call = call)
    x <- rlang::eval_tidy(expr[[3]], env = env)
    if (!rlang::is_string(x) || !nzchar(x)) {
      cli::cli_abort(
        "The value of {.code has()} must be a single non-empty string.",
        call = call
      )
    }
    # "field contains this value", for comma-joined multi-value fields such as
    # BAG gebruiksdoel. The value is matched literally: LIKE's wildcards (and
    # the backslash that escapes them) are escaped in the value.
    x <- gsub("([\\\\%_])", "\\\\\\1", x)
    pat <- cql_literal(paste0("%", x, "%"), call = call)
    if (!is.null(f$wrap)) {
      pat <- sprintf("%s(%s)", f$wrap, pat)
    }
    return(paste(f$text, "LIKE", pat))
  }

  if (fn == "between" && length(expr) == 4L) {
    f <- cql_field(expr[[2]], call = call)
    if (!is.null(f$wrap)) {
      cli::cli_abort(
        "{.code casei()}/{.code accenti()} are not supported with {.code between()}.",
        call = call
      )
    }
    lo <- cql_value(expr[[3]], env, NULL, call = call)
    hi <- cql_value(expr[[4]], env, NULL, call = call)
    return(paste(f$text, "BETWEEN", lo, "AND", hi))
  }

  if (fn == "is.na" && length(expr) == 2L) {
    f <- cql_field(expr[[2]], call = call)
    return(paste(f$text, "IS NULL"))
  }

  # Kept in a variable: cli escapes interpolated values, while literal </>
  # inside inline markup would break its glue parsing.
  supported <- "==, !=, <, <=, >, >=, %in%, &, |, !, has(), like(), between(), is.na(), casei(), accenti()"
  cli::cli_abort(
    c(
      "Unsupported function {.fn {fn}} in a filter expression.",
      "i" = "Supported: {supported}.",
      "i" = "For anything else, pass a CQL2 string to {.arg filter} directly."
    ),
    call = call
  )
}

#' Build a server-side attribute filter from R syntax
#'
#' Translates an R expression into a [CQL2](https://www.ogc.org/standards/cql2/)
#' text filter for the `filter` argument of [pdok_read()]. Field names are
#' written as bare names (see [pdok_list_queryables()] for the fields a layer
#' supports); values are taken from your R session, so variables and vectors
#' work as usual.
#'
#' @section Supported syntax:
#'
#' | R | CQL2 |
#' |---|---|
#' | `field == value`, `field != value` | `field = value`, `field <> value` |
#' | `field < v`, `field <= v`, `field > v`, `field >= v` | idem |
#' | `field %in% c(...)` | `field IN (...)` |
#' | `a & b`, `a \| b`, `!a` | `a AND b`, `a OR b`, `NOT (a)` |
#' | `has(field, "value")` | `field LIKE '%value%'` (field *contains* the value) |
#' | `like(field, "Lange%")` | `field LIKE 'Lange%'` (`%` = wildcard) |
#' | `between(field, lo, hi)` | `field BETWEEN lo AND hi` |
#' | `is.na(field)`, `!is.na(field)` | `field IS NULL`, `field IS NOT NULL` |
#' | `casei(field) == value` | `casei(field) = casei(value)` (case-insensitive) |
#' | `accenti(field) == value` | accent-insensitive comparison |
#'
#' `has()` matches the value anywhere in the field, with any wildcards in the
#' value escaped. It is made for fields that hold several comma-joined values,
#' such as `gebruiksdoel` in the BAG: `has(gebruiksdoel, "onderwijsfunctie")`
#' also matches a building registered as
#' `"logiesfunctie,onderwijsfunctie"`, where `==` would not.
#'
#' `has()`, `like()`, `between()`, `casei()` and `accenti()` only have meaning
#' inside `pdok_where()`; they are translated, never executed as R functions. The
#' left-hand side of a comparison is always the field, the right-hand side is
#' always an R value. For CQL2 features beyond this table, pass a CQL2 string
#' to `filter` directly.
#'
#' @section Finding field names and values:
#'
#' Only the fields a layer publishes as *queryables* can be filtered on.
#' [pdok_list_queryables()] lists them for one layer;
#' `pdok_list_layers(dataset, queryables = TRUE)` shows them for every layer
#' of a dataset at once. The *values* a field holds are not part of the API:
#' consult the dataset's own documentation (for the BAG, the
#' [Catalogus BAG](https://imbag.github.io/catalogus/) defines the permitted
#' values of fields such as `gebruiksdoel` and `status`), or read a small
#' sample of the layer with [pdok_read()] and inspect the column.
#'
#' @section Long `%in%` vectors:
#'
#' PDOK's servers reject over-long request URLs, so a `%in%` over more than
#' 300 values (after deduplication) is sent as multiple requests of 300 values
#' each, and [pdok_read()] combines the results. This happens automatically;
#' it does require that the `%in%` is combined with any other conditions by
#' `&` (not inside `|` or `!`), and at most one `%in%` per filter can be this
#' long. Row order follows the service, not your input vector.
#'
#' @param expr A filter expression (see *Supported syntax*).
#'
#' @return An object of class `pdok_where`, for the `filter` argument of
#'   [pdok_read()]. `as.character()` returns the CQL2 text it renders to (one
#'   string per batched request).
#' @seealso [pdok_read()], [pdok_list_queryables()].
#' @examples
#' pdok_where(postcode == "3811MZ")
#'
#' pdok_where(
#'   casei(woonplaats_naam) == "amersfoort" & like(openbare_ruimte_naam, "Lange%")
#' )
#'
#' # Values come from your session, so vectors and variables work:
#' codes <- c("3811MZ", "3811MS")
#' pdok_where(postcode %in% codes & status != "Naamgeving ingetrokken")
#'
#' # has(): the field contains the value (multi-value fields such as
#' # the BAG gebruiksdoel, where a building can have several uses)
#' pdok_where(has(gebruiksdoel, "onderwijsfunctie"))
#' @export
pdok_where <- function(expr) {
  quo <- rlang::enquo(expr)
  if (rlang::quo_is_missing(quo)) {
    cli::cli_abort("{.arg expr} must be a filter expression, e.g. {.code postcode == \"3811MZ\"}.")
  }
  ex <- rlang::quo_get_expr(quo)
  env <- rlang::quo_get_env(quo)

  state <- new.env(parent = emptyenv())
  state$found <- FALSE
  cql <- cql_render(ex, env, and_ctx = TRUE, state = state, call = environment())

  structure(
    list(
      cql = if (state$found) NULL else cql,
      expr = ex,
      env = env,
      in_field = if (state$found) state$field else NULL,
      in_values = if (state$found) state$values else NULL
    ),
    class = "pdok_where"
  )
}

# Internal: the CQL2 filter string(s) a `filter` argument stands for — a
# validated raw string as-is, a pdok_where as one rendered string, or one
# string per batch when it holds a long %in%.
filter_queries <- function(filter, call = rlang::caller_env()) {
  if (!inherits(filter, "pdok_where")) {
    return(filter)
  }
  if (is.null(filter$in_values)) {
    return(filter$cql)
  }
  chunks <- split(
    filter$in_values,
    ceiling(seq_along(filter$in_values) / pdok_in_batch_size)
  )
  vapply(
    chunks,
    function(ch) {
      cql_render(filter$expr, filter$env, and_ctx = TRUE, batch = ch, call = call)
    },
    character(1),
    USE.NAMES = FALSE
  )
}

#' @rdname pdok_where
#' @param x A `pdok_where` object.
#' @param ... Ignored.
#' @export
as.character.pdok_where <- function(x, ...) {
  filter_queries(x)
}

#' @rdname pdok_where
#' @export
print.pdok_where <- function(x, ...) {
  qs <- filter_queries(x)
  cat("<pdok_where> CQL2 filter:\n")
  cat(qs[[1]], "\n", sep = "")
  if (length(qs) > 1L) {
    cat(sprintf(
      "... and %d more batched request(s), %d values of %s in total\n",
      length(qs) - 1L, length(x$in_values), x$in_field
    ))
  }
  invisible(x)
}
