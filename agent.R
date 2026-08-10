# The devrel-io self-service agent: daily adoption and engagement metrics
# for Posit's open source projects, materialized from the devrel-io repo by
# etl/build-db.R.

library(commons)

source("agent-builder.R")

devrel_con <- DBI::dbConnect(
  duckdb::duckdb(),
  "data/devrel.duckdb",
  read_only = TRUE
)

devrel_agent <- build_devrel_agent(
  con = devrel_con,
  client = ellmer::chat_anthropic(
    model = "claude-sonnet-5",
    params = ellmer::params(reasoning_effort = "high")
  )
)
