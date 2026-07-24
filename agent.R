# The devrel-io self-service agent: daily adoption and engagement metrics
# for Posit's open source projects, materialized from the devrel-io repo by
# etl/build-db.R.

library(commons)

devrel_con <- DBI::dbConnect(
  duckdb::duckdb(),
  "data/devrel.duckdb",
  read_only = TRUE
)

devrel_agent <- commons(
  client = ellmer::chat_anthropic(model = "claude-sonnet-5"),
  data_sources = list(
    devrel = data_source(
      devrel_con,
      tables = c(
        "projects",
        "metrics",
        "metrics_filled",
        "indicators",
        "events",
        "content",
        "meta"
      ),
      dictionary = "dictionaries/devrel.data-dict.yaml"
    )
  )
)
