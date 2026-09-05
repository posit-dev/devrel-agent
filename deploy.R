withr::local_options(rsconnect.python.enabled = FALSE)

source("agent.R")

build_devrel_agent(
  con = devrel_con,
  client = ellmer::chat_openai(model = "gpt-5.6-terra")
)$prewarm()

rsconnect::deployApp(
  appPrimaryDoc = "app.R",
  appFiles = c(
    "DESCRIPTION",
    "app.R",
    "agent.R",
    "agent-builder.R",
    "instructions.md",
    "_brand.yml",
    "data/devrel.duckdb",
    list.files(
      c("_assets", "_fonts", "commons-cache", "dictionaries"),
      recursive = TRUE,
      full.names = TRUE
    )
  ),
  appId = "01a043bd-5dee-7f82-917c-531eec503648",
  account = "posit",
  server = "connect.posit.cloud",
  envVars = "OPENAI_API_KEY"
)
