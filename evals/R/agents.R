# Builders for the agents under evaluation and the grader client. Each eval
# sample gets a fresh agent (fresh conversation, handle store, and worker)
# over a shared read-only connection.

make_devrel_con <- function(db_path = "data/devrel.duckdb") {
  DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
}

# Mirrors agent.R, which is the deployed wiring; kept as a function so the
# solver can rebuild per sample and future variants (e.g. a no-dictionary
# arm) can branch here.
build_devrel_agent <- function(con, client_factory = make_solver_client) {
  commons::commons(
    client = client_factory(),
    data_sources = list(
      devrel = commons::data_source(
        con,
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
}

make_solver_client <- function() {
  ellmer::chat_anthropic(
    model = "claude-sonnet-5",
    params = ellmer::params(reasoning_effort = "high")
  )
}

# Thinking is disabled for grading (as in bluffbench2's scorer): the
# deterministic tools do the arithmetic, and default output budgets are
# easily exhausted by thinking over long trajectory-bearing prompts.
make_grader_client <- function() {
  ellmer::chat_anthropic(
    model = "claude-sonnet-5",
    api_args = list(thinking = list(type = "disabled"))
  )
}
