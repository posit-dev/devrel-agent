# Shared by the production app and evals so both exercise the same agent
# configuration; each supplies its own client and database connection.
build_devrel_agent <- function(con, client) {
  commons::commons(
    client = client,
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
    ),
    instructions = "instructions.md"
  )
}
