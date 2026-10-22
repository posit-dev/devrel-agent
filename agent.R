# The devrel-io self-service agent: daily adoption and engagement metrics
# for Posit's open source projects, exported from the devrel-io repo with its
# data dictionary by etl/build-db.R (velocirepo export).
# Production runtime setup lives here. The agent definition is separate so the
# app and evals exercise the same configuration.

library(commons)

options(commons.context_cache = "commons-cache")

source("agent-builder.R", local = TRUE)

# Shared read-only connection. Shiny's event loop is single-threaded, so
# sessions never query it concurrently; agents are built per session in app.R.
devrel_con <- DBI::dbConnect(
  duckdb::duckdb(),
  "data/velocirepo.duckdb",
  read_only = TRUE
)
