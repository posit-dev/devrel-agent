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
    # Project and site prose crawled from opensource.posit.co.
    context_layer = commons::context_layer(
      files = list.files(
        "context",
        pattern = "[.]md$",
        recursive = TRUE,
        full.names = TRUE
      )
    ),
    instructions = "instructions.md"
  )
}
