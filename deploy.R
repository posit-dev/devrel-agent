# Deploys the agent, with data/velocirepo.duckdb and data/data-dict.yaml, to
# Connect Cloud. The nightly workflow runs it after velocirepo export; it
# works the same from a laptop. With DEVREL_DEPLOY=false it checks and
# prewarms without deploying, as the workflow does for pull requests.

withr::local_options(rsconnect.python.enabled = FALSE)

source("agent.R")

# The Connect Cloud account the app is published to, and the app's id there:
# the repository variable CONNECT_CLOUD_APP_ID in CI, or a line in .env,
# which agent.R reads. Without an id, a new app is created, which only a run
# started by hand may do: a nightly run would create one every night.
account <- "jeroenjanssens"
app_id <- Sys.getenv("CONNECT_CLOUD_APP_ID")
if (!nzchar(app_id) && identical(Sys.getenv("GITHUB_EVENT_NAME"), "schedule")) {
  cli::cli_abort(c(
    "{.envvar CONNECT_CLOUD_APP_ID} isn't set, so this run would create a new app.",
    i = "Deploy once by hand, then set the repository variable to the app's id."
  ))
}

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

# Every deploy sends the app's variables, and Connect Cloud replaces the app's
# variables with them: rsconnect sends an empty list without envVars, which
# removes OPENAI_API_KEY. So the key is required here, from .env or the
# repository secret.
if (!nzchar(Sys.getenv("OPENAI_API_KEY"))) {
  cli::cli_abort(c(
    "{.envvar OPENAI_API_KEY} isn't set.",
    i = "Deploying without it would remove it from the app on Connect Cloud."
  ))
}

# In CI, log in with the Connect Cloud client credentials of the repository
# secrets; locally, rsconnect uses the account it already has.
if (nzchar(Sys.getenv("CONNECT_CLOUD_CLIENT_ID"))) {
  rsconnect::connectCloudClientCredentials(
    clientId = Sys.getenv("CONNECT_CLOUD_CLIENT_ID"),
    clientSecret = Sys.getenv("CONNECT_CLOUD_CLIENT_SECRET"),
    accountName = account
  )
}

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
  appId = if (nzchar(app_id)) app_id,
  appName = "devrel-agent",
  appTitle = "DevRel Agent",
  account = account,
  server = "connect.posit.cloud",
  envVars = "OPENAI_API_KEY",
  forceUpdate = TRUE
)

if (!nzchar(app_id)) {
  created <- rsconnect::deployments(".", accountFilter = account, serverFilter = "connect.posit.cloud")
  new_id <- if ("appId" %in% names(created)) created$appId[[1]] else "(see the URL)"
  cli::cli_inform(c(
    "v" = "Created the app {.val {new_id}} at {.url {created$url[[1]]}}.",
    i = "Set its id as the repository variable: {.code gh variable set CONNECT_CLOUD_APP_ID --body <id>}"
  ))
}
