# Export the devrel-io velocirepo data as a standalone DuckDB with its data
# dictionary.
#
# velocirepo (>= 1.2.0) writes both: `velocirepo export --format duckdb`
# materializes every table as plain data (no views, no JSON-typed columns, so
# the artifact is portable and readable without DuckDB's json extension), and
# `--data-dict` writes data-dict.yaml from the schema, the source metadata, the
# data and the [data_dict] section of devrel-io's velocirepo.toml. Caveats
# about devrel-io's data belong in that section, not here.
#
# Usage:
#   Rscript etl/build-db.R [devrel_io] [output_dir]

build_devrel_db <- function(
  devrel_io = "inst/devrel-io",
  output_dir = "data"
) {
  config <- file.path(devrel_io, "velocirepo.toml")
  if (!file.exists(config)) {
    cli::cli_abort("No velocirepo config found at {.path {config}}.")
  }
  if (Sys.which("velocirepo") == "") {
    cli::cli_abort("velocirepo isn't installed; see https://posit-dev.github.io/velocirepo/user-guide/installation.html.")
  }

  status <- system2(
    "velocirepo",
    c(
      "--config", shQuote(config),
      "export", shQuote(output_dir),
      "--format", "duckdb",
      "--data-dict"
    )
  )
  if (status != 0) {
    cli::cli_abort("{.code velocirepo export} failed with status {status}.")
  }

  output <- file.path(output_dir, "velocirepo.duckdb")
  check_build(output)
  invisible(output)
}

check_build <- function(output, call = rlang::caller_env()) {
  con <- DBI::dbConnect(duckdb::duckdb(), output, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # devrel-io has data in every table; an empty one means a broken export.
  tables <- c(
    "projects", "targets", "events", "metrics", "content", "metrics_filled",
    "indicators"
  )
  for (table in tables) {
    n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", table))$n
    if (n == 0) {
      cli::cli_abort("Exported table {.field {table}} is empty.", call = call)
    }
  }

  as_of <- DBI::dbGetQuery(con, "SELECT as_of FROM meta")$as_of
  if (as_of < Sys.Date() - 30) {
    cli::cli_warn(
      "Data is stale: most recent metric date is {as_of}.
       Refresh the devrel-io clone."
    )
  }
}

if (!interactive() && identical(environment(), globalenv())) {
  args <- commandArgs(trailingOnly = TRUE)
  do.call(build_devrel_db, as.list(args))
}
