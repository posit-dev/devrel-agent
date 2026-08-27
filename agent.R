# The devrel-io self-service agent: daily adoption and engagement metrics
# for Posit's open source projects, materialized from the devrel-io repo by
# etl/build-db.R.
# Production runtime setup lives here. The agent definition is separate so the
# app and evals exercise the same configuration.

library(commons)

source("agent-builder.R")

devrel_con <- DBI::dbConnect(
  duckdb::duckdb(),
  "data/devrel.duckdb",
  read_only = TRUE
)

devrel_agent <- build_devrel_agent(
  con = devrel_con,
  client = ellmer::chat_openai(
    model = "gpt-5.6-terra",
    params = ellmer::params(reasoning_effort = "medium")
  )
)
