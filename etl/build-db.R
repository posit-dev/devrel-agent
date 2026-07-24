# Materialize the devrel-io velocirepo data into a compact, standalone DuckDB.
#
# The source velocirepo.duckdb ships views whose read_json() calls hardcode
# absolute paths from the machine that built it, and querying them re-parses
# the JSONL every time. This script extracts those view definitions, rewrites
# the path prefix to `data_dir`, and materializes each view as a plain table
# in `output`, so agent queries pay no JSONL parsing and the artifact is
# portable. The view SQL is always taken from the source database, never
# copied here, so velocirepo's semantics are tracked automatically.
#
# Usage:
#   Rscript etl/build-db.R [data_dir] [output]

build_devrel_db <- function(
  data_dir = "inst/devrel-io/velocirepo/data",
  output = "data/devrel.duckdb"
) {
  source_db <- file.path(data_dir, "velocirepo.duckdb")
  if (!file.exists(source_db)) {
    cli::cli_abort("No velocirepo database found at {.path {source_db}}.")
  }

  views <- read_view_definitions(source_db)
  views$sql <- rewrite_data_paths(views$sql, normalizePath(data_dir))

  unlink(c(output, paste0(output, ".wal")))
  dir.create(dirname(output), showWarnings = FALSE, recursive = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con))
  load_json_extension(con)
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS src (READ_ONLY)", source_db))
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS out", output))

  for (sql in views$sql) {
    DBI::dbExecute(con, sql)
  }

  DBI::dbExecute(con, "CREATE TABLE out.projects AS SELECT * FROM src.projects")

  # Materialize in dependency order, repointing each view at its materialized
  # table as we go so every JSONL glob is parsed exactly once: `metrics`
  # unions over `events`, and `metrics_filled`/`indicators` build on
  # `metrics`. `__velocirepo_metric_watermarks` is left as a view; it's tiny
  # and only consulted while materializing `metrics_filled`.
  for (name in c("events", "metrics", "content", "metrics_filled", "indicators")) {
    DBI::dbExecute(
      con,
      sprintf("CREATE TABLE out.%s AS SELECT * FROM %s", name, name)
    )
    DBI::dbExecute(
      con,
      sprintf("CREATE OR REPLACE VIEW %s AS SELECT * FROM out.%s", name, name)
    )
  }

  DBI::dbExecute(
    con,
    "CREATE TABLE out.meta AS
     SELECT (SELECT MAX(date) FROM out.metrics) AS as_of,
            current_timestamp AS built_at"
  )

  check_build(con)
  report_build(con, output)
  invisible(output)
}

read_view_definitions <- function(source_db, call = rlang::caller_env()) {
  src <- DBI::dbConnect(duckdb::duckdb(), source_db, read_only = TRUE)
  on.exit(DBI::dbDisconnect(src))

  views <- DBI::dbGetQuery(
    src,
    "SELECT view_name, sql FROM duckdb_views()
     WHERE NOT internal AND schema_name = 'main' AND NOT temporary"
  )

  needed <- c(
    "__velocirepo_metric_watermarks",
    "events",
    "metrics",
    "metrics_filled",
    "indicators",
    "content"
  )
  missing <- setdiff(needed, views$view_name)
  if (length(missing) > 0) {
    cli::cli_abort(
      "Source database is missing expected view{?s} {.val {missing}}.",
      call = call
    )
  }
  views[match(needed, views$view_name), ]
}

# The baked prefix is whatever precedes the metrics glob in the source SQL,
# e.g. '/home/runner/work/devrel-io/devrel-io/velocirepo/data'.
rewrite_data_paths <- function(sql, data_dir, call = rlang::caller_env()) {
  pattern <- "read_json\\('([^']+)/metrics/\\*"
  match <- regmatches(sql, regexec(pattern, sql))
  prefixes <- unique(unlist(lapply(match, function(m) m[2])))
  prefixes <- prefixes[!is.na(prefixes)]

  if (length(prefixes) != 1) {
    cli::cli_abort(
      c(
        "Expected one baked data path prefix in the source views, found
         {length(prefixes)}.",
        "i" = "Prefixes: {.path {prefixes}}"
      ),
      call = call
    )
  }

  gsub(prefixes, data_dir, sql, fixed = TRUE)
}

load_json_extension <- function(con, call = rlang::caller_env()) {
  tryCatch(
    DBI::dbExecute(con, "INSTALL json; LOAD json;"),
    error = function(e) {
      cli::cli_abort(
        "Failed to install DuckDB's json extension (network needed once).",
        parent = e,
        call = call
      )
    }
  )
  invisible(con)
}

check_build <- function(con, call = rlang::caller_env()) {
  tables <- c(
    "projects", "events", "metrics", "content", "metrics_filled", "indicators"
  )
  for (table in tables) {
    n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM out.%s", table))$n
    if (n == 0) {
      cli::cli_abort("Materialized table {.field {table}} is empty.", call = call)
    }
  }

  as_of <- DBI::dbGetQuery(con, "SELECT as_of FROM out.meta")$as_of
  if (as_of < Sys.Date() - 30) {
    cli::cli_warn(
      "Data is stale: most recent metric date is {as_of}.
       Refresh the devrel-io clone."
    )
  }
}

report_build <- function(con, output) {
  counts <- DBI::dbGetQuery(
    con,
    "SELECT table_name, estimated_size AS rows FROM duckdb_tables()
     WHERE database_name = 'out' ORDER BY table_name"
  )
  as_of <- DBI::dbGetQuery(con, "SELECT as_of FROM out.meta")$as_of

  cli::cli_inform(c(
    "v" = "Built {.path {output}} ({prettyunits::pretty_bytes(file.size(output))}),
           data as of {as_of}.",
    stats::setNames(
      sprintf("%s: %s rows", counts$table_name, format(counts$rows, big.mark = ",")),
      rep("*", nrow(counts))
    )
  ))
}

if (!interactive() && identical(environment(), globalenv())) {
  args <- commandArgs(trailingOnly = TRUE)
  do.call(build_devrel_db, as.list(args))
}
