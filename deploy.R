deploy_agent <- function(
  app_id = "01a03ed8-65f0-408b-ccec-53789a51c2f2",
  server = "connect.posit.cloud",
  env_vars = "OPENAI_API_KEY",
  dry_run = FALSE,
  log_level = c("normal", "verbose", "quiet")
) {
  log_level <- match.arg(log_level)
  root <- normalizePath(".", mustWork = TRUE)
  app_files <- agent_app_files(root)

  if (dry_run) {
    cli::cli_h2("Dry run")
    cli::cli_inform(c(
      "i" = "App directory: {.path {root}}",
      "i" = "App files: {length(app_files)}",
      "i" = paste(
        "Bundle contents:",
        prettyunits::pretty_bytes(sum(file.size(file.path(root, app_files))))
      )
    ))
    cli::cli_ul(app_files)
    return(invisible(app_files))
  }

  missing_env_vars <- env_vars[!nzchar(Sys.getenv(env_vars))]
  if (length(missing_env_vars) > 0) {
    cli::cli_abort(
      "Environment variable{?s} {.envvar {missing_env_vars}} must be set."
    )
  }

  if (!server %in% rsconnect::servers()$name) {
    cli::cli_abort(c(
      "rsconnect server {.val {server}} is not registered.",
      "i" = "Register it with {.fn rsconnect::addServer} and {.fn rsconnect::connectApiUser}."
    ))
  }

  # Positron sets this for local Python support, prompting an unnecessary scan.
  withr::with_envvar(
    c(RETICULATE_PYTHON = "", RETICULATE_PYTHON_FALLBACK = ""),
    rsconnect::deployApp(
      appDir = root,
      appFiles = app_files,
      appPrimaryDoc = "app.R",
      appMode = "shiny",
      appTitle = "DevRel Agent",
      appId = app_id,
      server = server,
      envVars = env_vars,
      dependencyResolution = "library",
      quarto = FALSE,
      forceUpdate = TRUE,
      logLevel = log_level
    )
  )
}

agent_app_files <- function(root = normalizePath(".", mustWork = TRUE)) {
  files <- c(
    "app.R",
    "agent.R",
    "agent-builder.R",
    "deploy.R",
    "instructions.md",
    "data/devrel.duckdb",
    app_files_in_dir(root, "dictionaries", pattern = "[.]ya?ml$")
  )
  missing <- files[!file.exists(file.path(root, files))]
  if (length(missing) > 0) {
    cli::cli_abort("Missing deployment file{?s}: {.path {missing}}.")
  }
  files
}

app_files_in_dir <- function(root, directory, pattern = NULL) {
  file.path(
    directory,
    list.files(
      file.path(root, directory),
      pattern = pattern,
      recursive = TRUE
    )
  )
}

requireNamespace("shinychat", quietly = TRUE)
requireNamespace("bsicons", quietly = TRUE)
requireNamespace("htmltools", quietly = TRUE)
