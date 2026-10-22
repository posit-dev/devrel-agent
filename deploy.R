# Deploys the agent, with data/velocirepo.duckdb and data/data-dict.yaml, to
# Connect Cloud. The nightly workflow runs it after velocirepo export; it
# works the same from a laptop. With DEVREL_DEPLOY=false it checks and
# prewarms without deploying, as the workflow does for pull requests.

withr::local_options(rsconnect.python.enabled = FALSE)

source("agent.R")

# A stale database means devrel-io's nightly fetch stopped: don't deploy, so
# that the failure gets noticed. The running version has the same data.
as_of <- DBI::dbGetQuery(devrel_con, "SELECT as_of FROM meta")$as_of
if (as_of < Sys.Date() - 3) {
  cli::cli_abort("The data is stale: the latest metric date is {as_of}.")
}

# Builds the context search index in commons-cache/, which ships with the
# app. It calls no model, so it needs no API key.
build_devrel_agent(
  con = devrel_con,
  client = ellmer::chat_openai(model = "gpt-5.6-terra")
)$prewarm()

if (identical(Sys.getenv("DEVREL_DEPLOY"), "false")) {
  cli::cli_inform("Checked and prewarmed the data of {as_of}; not deploying.")
  quit(save = "no")
}

# In CI, log in with the Connect Cloud client credentials of the repository
# secrets; locally, rsconnect uses the account it already has.
if (nzchar(Sys.getenv("CONNECT_CLOUD_CLIENT_ID"))) {
  rsconnect::connectCloudClientCredentials(
    clientId = Sys.getenv("CONNECT_CLOUD_CLIENT_ID"),
    clientSecret = Sys.getenv("CONNECT_CLOUD_CLIENT_SECRET"),
    accountName = "posit"
  )
}

# OPENAI_API_KEY is set in the app's Content Settings on Connect Cloud, so
# it never passes through the machine that deploys.
rsconnect::deployApp(
  appPrimaryDoc = "app.R",
  appFiles = c(
    "DESCRIPTION",
    "app.R",
    "agent.R",
    "agent-builder.R",
    "instructions.md",
    "_brand.yml",
    "data/velocirepo.duckdb",
    "data/data-dict.yaml",
    list.files(
      c("_assets", "_fonts", "commons-cache"),
      recursive = TRUE,
      full.names = TRUE
    )
  ),
  appId = "01a043bd-5dee-7f82-917c-531eec503648",
  account = "posit",
  server = "connect.posit.cloud",
  forceUpdate = TRUE
)
