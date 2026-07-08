# Shared HTTP mocks. resolve_dataset() now looks a registry id up in the live
# index, so any test that loads layers/features must also mock the index. The
# dispatcher routes each request to the right canned response by URL.

mock_index_body <- function() {
  paste0(
    '{"apis":[',
    '{"title":"CBS Gebiedsindelingen","description":"Administrative boundaries.",',
    '"keywords":["gemeente","provincie"],',
    '"links":[{"rel":"root","href":"https://api.pdok.nl/cbs/gebiedsindelingen/ogc/v1"}]},',
    '{"title":"BAG","description":"Buildings and addresses.",',
    '"keywords":["bag","adres"],',
    '"links":[{"rel":"root","href":"https://api.pdok.nl/kadaster/bag/ogc/v2"}]}',
    ']}'
  )
}

mock_index_resp <- function() {
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/index.json",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(mock_index_body())
  )
}

# An OGC /conformance response. With features = TRUE it advertises the OGC API
# Features core class; with FALSE it advertises only tiles (a non-Features
# dataset such as a tile service).
mock_conformance_resp <- function(features = TRUE) {
  classes <- if (features) {
    c(
      "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/core",
      "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/geojson"
    )
  } else {
    c(
      "http://www.opengis.net/spec/ogcapi-tiles-1/1.0/conf/core",
      "http://www.opengis.net/spec/ogcapi-common-2/1.0/conf/collections"
    )
  }
  body <- paste0(
    '{"conformsTo":[',
    paste(sprintf('"%s"', classes), collapse = ","),
    ']}'
  )
  httr2::response(
    status_code = 200,
    url = "https://api.pdok.nl/x/ogc/v1/conformance",
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(body)
  )
}

# Build a mock function for httr2::local_mocked_responses() that dispatches by
# URL. Pass the canned responses you expect this test to need.
mock_pdok_dispatcher <- function(index = mock_index_resp(),
                                 collections = NULL, items = NULL,
                                 conformance = NULL, locatieserver = NULL) {
  function(req) {
    url <- req$url
    if (grepl("index\\.json", url)) return(index)
    if (grepl("/conformance", url)) return(conformance)
    if (grepl("/collections/[^/]+/items", url)) return(items)
    if (grepl("/collections", url)) return(collections)
    if (grepl("locatieserver", url)) return(locatieserver)
    cli::cli_abort("Unexpected mock request: {url}")
  }
}
