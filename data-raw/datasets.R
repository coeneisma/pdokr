# Regenerate the bundled PDOK dataset snapshot from the live index.
#
# The snapshot is the offline fallback for fetch_index(). Re-run this script
# whenever PDOK publishes new datasets:
#
#   source("data-raw/datasets.R")

devtools::load_all(quiet = TRUE)

resp <- pdok_perform(pdok_request(pdok_base_urls$index))
pdok_datasets_snapshot <- parse_index(httr2::resp_body_json(resp))

usethis::use_data(pdok_datasets_snapshot, internal = TRUE, overwrite = TRUE)
