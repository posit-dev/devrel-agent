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
