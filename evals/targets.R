# Computes the machine-derived grading facts for evals/questions.yaml, which
# references them as {placeholders}. Targets are snapshot-scoped: they are
# correct for the data/devrel.duckdb the solver queries.
#
# Usage:
#   Rscript evals/targets.R author   # (re)write evals/targets.yaml
#   Rscript evals/targets.R audit    # recompute and diff against the stored file

targets_path <- "evals/targets.yaml"

dedup_where <- paste(
  "project NOT IN ('shiny', 'py-shiny', 'orbital', 'pointblank')",
  "AND NOT (project = 'orbital-python' AND source = 'github')",
  "AND NOT (project = 'shiny-r' AND target IN ('posit/shiny', 'shiny.posit.co'))"
)

fmt <- function(x) {
  format(round(as.numeric(x)), big.mark = ",", scientific = FALSE, trim = TRUE)
}

fmt_rows <- function(df, label, value) {
  paste(sprintf("%s: %s", df[[label]], vapply(df[[value]], fmt, character(1))), collapse = "; ")
}

compute_targets <- function(con) {
  q <- function(sql) DBI::dbGetQuery(con, sql)
  q1 <- function(sql) q(sql)[[1]][[1]]

  snapshot_date <- as.character(q1("SELECT MAX(date) FROM metrics"))

  dplyr_month <- function(from, to) {
    q1(sprintf(
      "SELECT SUM(value) FROM metrics
       WHERE project = 'dplyr' AND source = 'cran' AND metric = 'daily_downloads'
         AND date >= '%s' AND date <= '%s'",
      from, to
    ))
  }

  monthly <- q(
    "SELECT strftime(date_trunc('month', date), '%Y-%m') AS month, SUM(value) AS downloads
     FROM metrics
     WHERE project = 'dplyr' AND source = 'cran' AND metric = 'daily_downloads'
       AND date >= '2024-07-01' AND date < '2026-07-01'
     GROUP BY 1 ORDER BY 1"
  )
  yearly <- q(
    "SELECT EXTRACT(year FROM date) AS year, SUM(value) AS downloads
     FROM metrics
     WHERE project = 'dplyr' AND source = 'cran' AND metric = 'daily_downloads'
     GROUP BY 1 ORDER BY 1"
  )

  site_visitors_ytd <- q1(
    "SELECT SUM(value) FROM metrics
     WHERE project = 'shiny-python' AND target = 'shiny.posit.co'
       AND metric = 'daily_site_visitors' AND date >= '2026-01-01'"
  )
  site_visitors_double <- q1(
    "SELECT SUM(value) FROM metrics
     WHERE target = 'shiny.posit.co' AND date >= '2026-01-01'
       AND (metric = 'daily_site_visitors' OR (metric = 'daily_visitors' AND page IS NULL))"
  )

  stars_ytd <- q(sprintf(
    "SELECT project, SUM(value) AS stars FROM metrics
     WHERE metric = 'daily_stars' AND date >= '2026-01-01' AND %s
     GROUP BY project ORDER BY stars DESC LIMIT 5",
    dedup_where
  ))

  channel <- q(
    "SELECT value, date FROM metrics
     WHERE metric = 'total_channel_views'
     ORDER BY date DESC LIMIT 1"
  )
  per_video <- q(
    "WITH latest AS (
       SELECT video_id, MAX(date) AS d FROM metrics
       WHERE source = 'youtube' AND metric = 'total_views' AND video_id IS NOT NULL
       GROUP BY video_id)
     SELECT SUM(m.value) AS views, MAX(l.d) AS as_of
     FROM metrics m JOIN latest l ON m.video_id = l.video_id AND m.date = l.d
     WHERE m.source = 'youtube' AND m.metric = 'total_views'"
  )

  pages <- function(from) {
    q(sprintf(
      "SELECT page, SUM(value) AS pageviews FROM metrics
       WHERE project = 'shiny-python' AND target = 'shiny.posit.co'
         AND metric = 'daily_pageviews' AND page IS NOT NULL AND date >= '%s'
       GROUP BY page ORDER BY pageviews DESC LIMIT 5",
      from
    ))
  }

  # The duplicate id's page rows start at the 2026-06-23 seam, so a naive
  # two-id sum doubles a recent window but inflates the full window only
  # ~1.16x; the grading notes need both signatures to catch the double-count.
  pages_naive_full <- q(
    "SELECT page, SUM(value) AS pageviews FROM metrics
     WHERE target = 'shiny.posit.co'
       AND metric = 'daily_pageviews' AND page IS NOT NULL
     GROUP BY page ORDER BY pageviews DESC LIMIT 5"
  )

  videos <- q(
    "WITH latest AS (
       SELECT video_id, MAX(date) AS d FROM metrics
       WHERE source = 'youtube' AND metric = 'total_views' AND video_id IS NOT NULL
       GROUP BY video_id)
     SELECT c.title, m.value AS views
     FROM metrics m
     JOIN latest l ON m.video_id = l.video_id AND m.date = l.d
     LEFT JOIN content c ON c.id = m.video_id
     WHERE m.source = 'youtube' AND m.metric = 'total_views'
     ORDER BY views DESC LIMIT 2"
  )

  downloads_june <- function(source) {
    q1(sprintf(
      "SELECT SUM(value) FROM metrics
       WHERE source = '%s' AND metric = 'daily_downloads'
         AND date BETWEEN '2026-06-01' AND '2026-06-30' AND %s",
      source, dedup_where
    ))
  }

  orbital <- list(
    cran = q(
      "SELECT SUM(value) AS total, MIN(date) AS start,
              SUM(value) FILTER (WHERE date >= '2025-02-25') AS since_feb25,
              SUM(value) FILTER (WHERE date >= '2026-01-01') AS ytd
       FROM metrics
       WHERE project = 'orbital-r' AND source = 'cran' AND metric = 'daily_downloads'"
    ),
    pypi = q(
      "SELECT SUM(value) AS total, MIN(date) AS start,
              SUM(value) FILTER (WHERE date >= '2026-01-01') AS ytd
       FROM metrics
       WHERE project = 'orbital-python' AND source = 'pypi' AND metric = 'daily_downloads'"
    ),
    stars_dedup = q1(sprintf(
      "SELECT SUM(value) FROM metrics
       WHERE metric = 'daily_stars' AND project LIKE 'orbital%%' AND %s",
      dedup_where
    )),
    stars_naive = q1(
      "SELECT SUM(value) FROM metrics
       WHERE metric = 'daily_stars' AND project IN ('orbital', 'orbital-r', 'orbital-python')"
    )
  )

  shiny_matched <- q(
    "SELECT project, SUM(value) AS downloads FROM metrics
     WHERE metric = 'daily_downloads' AND date >= '2025-06-04'
       AND ((project = 'shiny-r' AND source = 'cran') OR
            (project = 'shiny-python' AND source = 'pypi'))
     GROUP BY project"
  )
  shiny_stars_yearly <- q(
    "SELECT EXTRACT(year FROM date) AS year,
            SUM(value) FILTER (WHERE project = 'shiny-r' AND target = 'rstudio/shiny') AS shiny_r,
            SUM(value) FILTER (WHERE project = 'shiny-python') AS shiny_python
     FROM metrics
     WHERE metric = 'daily_stars' AND date >= '2023-01-01'
     GROUP BY 1 ORDER BY 1"
  )

  hadley_candidates <- q(
    "SELECT project, COUNT(*) AS n FROM events
     WHERE username = 'hadley'
       AND project IN ('ellmer', 'ggsql', 'btw', 'mcptools', 'vitals', 'shinychat', 'querychat')
     GROUP BY project ORDER BY n DESC"
  )
  ellmer_cran <- q1(
    "SELECT SUM(value) FROM metrics
     WHERE project = 'ellmer' AND source = 'cran' AND metric = 'daily_downloads'"
  )
  ggsql_stars <- q1(
    "SELECT SUM(value) FROM metrics
     WHERE project = 'ggsql' AND metric = 'daily_stars' AND date >= '2026-01-01'"
  )

  joint_pr <- q(
    "SELECT project,
            COUNT(*) FILTER (WHERE username = 'hadley') AS hadley,
            COUNT(*) FILTER (WHERE username = 'jcheng5') AS joe
     FROM events
     WHERE type IN ('pr_open', 'pr_merge') AND username IN ('hadley', 'jcheng5')
     GROUP BY project
     HAVING hadley > 0 AND joe > 0
     ORDER BY hadley + joe DESC LIMIT 8"
  )

  dplyr_docs <- q1(
    "SELECT SUM(value) FROM metrics
     WHERE target = 'dplyr.tidyverse.org' AND date BETWEEN '2026-06-01' AND '2026-06-30'
       AND (metric = 'daily_site_visitors' OR (metric = 'daily_visitors' AND page IS NULL))"
  )

  contributors <- q(sprintf(
    "SELECT username, COUNT(*) AS n FROM events
     WHERE project IN ('shiny', 'shiny-r', 'shiny-python', 'py-shiny')
       AND type NOT IN ('star', 'fork') AND %s
     GROUP BY username ORDER BY n DESC LIMIT 6",
    dedup_where
  ))

  positron_star_dates <- q(
    "SELECT date FROM metrics
     WHERE project = 'positron' AND metric = 'daily_stars' ORDER BY date"
  )$date
  gaps <- diff(positron_star_dates)
  gap_i <- which.max(gaps)
  positron_visitors <- function(from, to) {
    q1(sprintf(
      "SELECT SUM(value) FROM metrics
       WHERE project = 'positron' AND target = 'positron.posit.co'
         AND date BETWEEN '%s' AND '%s'
         AND (metric = 'daily_site_visitors' OR (metric = 'daily_visitors' AND page IS NULL))",
      from, to
    ))
  }

  latest_cran <- q(sprintf(
    "SELECT date, SUM(value) AS downloads FROM metrics
     WHERE source = 'cran' AND metric = 'daily_downloads' AND %s
     GROUP BY date ORDER BY date DESC LIMIT 1",
    dedup_where
  ))

  pair_ytd <- function(project, source) {
    q1(sprintf(
      "SELECT SUM(value) FROM metrics
       WHERE project = '%s' AND source = '%s' AND metric = 'daily_downloads'
         AND date >= '2026-01-01'",
      project, source
    ))
  }
  pairs <- list(
    c("chatlas", "pypi", "ellmer", "cran"),
    c("great-tables", "pypi", "gt", "cran"),
    c("pointblank-python", "pypi", "pointblank-r", "cran"),
    c("orbital-python", "pypi", "orbital-r", "cran"),
    c("querychat", "pypi", "querychat", "cran")
  )
  pairs_ytd <- vapply(pairs, function(p) {
    sprintf("%s %s PyPI vs %s %s CRAN", p[1], fmt(pair_ytd(p[1], p[2])), p[3], fmt(pair_ytd(p[3], p[4])))
  }, character(1))
  matched_totals <- q(
    "SELECT source, SUM(value) AS downloads FROM metrics
     WHERE metric = 'daily_downloads' AND date >= '2025-06-04'
       AND project IN ('chatlas', 'ellmer', 'great-tables', 'gt', 'pointblank-python',
                       'pointblank-r', 'orbital-python', 'orbital-r', 'querychat',
                       'shiny-r', 'shiny-python')
     GROUP BY source ORDER BY source"
  )

  tag_stats <- q(
    "SELECT COUNT(*) AS n_projects,
            COUNT(*) FILTER (WHERE len(tags) > 0) AS n_tagged,
            COUNT(*) FILTER (WHERE list_contains(tags, 'python')) AS n_python
     FROM projects"
  )
  pypi_roster <- q("SELECT DISTINCT project FROM metrics WHERE source = 'pypi' ORDER BY project")

  positron_sources <- q("SELECT DISTINCT source FROM metrics WHERE project = 'positron' ORDER BY source")

  may_videos <- q(
    "WITH latest AS (
       SELECT video_id, MAX(date) AS d FROM metrics
       WHERE source = 'youtube' AND metric = 'total_views' AND video_id IS NOT NULL
       GROUP BY video_id)
     SELECT COUNT(*) AS n, SUM(m.value) AS views
     FROM content c
     JOIN latest l ON l.video_id = c.id
     JOIN metrics m ON m.video_id = l.video_id AND m.date = l.d AND m.metric = 'total_views'
     WHERE c.published_at >= '2026-05-01' AND c.published_at < '2026-06-01'"
  )

  tidyverse_repos <- q(
    "SELECT DISTINCT target FROM events
     WHERE target LIKE 'tidyverse/%' ORDER BY target"
  )

  workflows_target <- q1("SELECT DISTINCT target FROM metrics WHERE project = 'workflows' AND source = 'github'")

  list(
    snapshot_date = snapshot_date,
    q01_june_2026 = fmt(dplyr_month("2026-06-01", "2026-06-30")),
    q01_june_2025 = fmt(dplyr_month("2025-06-01", "2025-06-30")),
    q02_monthly = fmt_rows(monthly, "month", "downloads"),
    q02_yearly = fmt_rows(yearly, "year", "downloads"),
    q03_ytd_visitor_days = fmt(site_visitors_ytd),
    q03_double_count = fmt(site_visitors_double),
    q04_leaderboard = fmt_rows(stars_ytd, "project", "stars"),
    q05_channel_views = fmt(channel$value),
    q05_channel_asof = as.character(channel$date),
    q05_per_video_sum = fmt(per_video$views),
    q06_pages_last31 = fmt_rows(pages("2026-06-23"), "page", "pageviews"),
    q06_pages_full = fmt_rows(pages("2026-03-02"), "page", "pageviews"),
    q06_pages_naive_full = fmt_rows(pages_naive_full, "page", "pageviews"),
    q07_top_video = sprintf("\"%s\" with %s views", videos$title[1], fmt(videos$views[1])),
    q07_runner_up = sprintf("\"%s\" with %s views", videos$title[2], fmt(videos$views[2])),
    q08_cran_june = fmt(downloads_june("cran")),
    q08_pypi_june = fmt(downloads_june("pypi")),
    q09_cran = sprintf(
      "CRAN (orbital-r): series starts %s, %s total, %s since 2025-02-25, %s in 2026 YTD",
      orbital$cran$start, fmt(orbital$cran$total), fmt(orbital$cran$since_feb25), fmt(orbital$cran$ytd)
    ),
    q09_pypi = sprintf(
      "PyPI (orbital-python): series starts %s (collection began 2025-06), %s total, %s in 2026 YTD",
      orbital$pypi$start, fmt(orbital$pypi$total), fmt(orbital$pypi$ytd)
    ),
    q09_stars = sprintf(
      "github stars all-time: %s deduplicated vs %s summed naively across the three orbital ids",
      fmt(orbital$stars_dedup), fmt(orbital$stars_naive)
    ),
    q11_downloads_matched = sprintf(
      "downloads since 2025-06-04 (PyPI collection start): shiny (CRAN) %s vs shiny for python (PyPI) %s",
      fmt(shiny_matched$downloads[shiny_matched$project == "shiny-r"]),
      fmt(shiny_matched$downloads[shiny_matched$project == "shiny-python"])
    ),
    q11_stars_yearly = paste(
      sprintf(
        "%d: rstudio/shiny %s vs py-shiny %s",
        shiny_stars_yearly$year,
        vapply(shiny_stars_yearly$shiny_r, fmt, character(1)),
        vapply(shiny_stars_yearly$shiny_python, fmt, character(1))
      ),
      collapse = "; "
    ),
    q12_hadley_events = fmt_rows(hadley_candidates, "project", "n"),
    q12_ellmer_cran = fmt(ellmer_cran),
    q12_ggsql_stars = fmt(ggsql_stars),
    q13_joint_pr = paste(
      sprintf(
        "%s (hadley %s / joe %s)",
        joint_pr$project,
        vapply(joint_pr$hadley, fmt, character(1)),
        vapply(joint_pr$joe, fmt, character(1))
      ),
      collapse = "; "
    ),
    q14_dplyr_june = fmt(dplyr_month("2026-06-01", "2026-06-30")),
    q14_docs_visitors_june = fmt(dplyr_docs),
    q15_contributors = fmt_rows(contributors, "username", "n"),
    q16_star_gap = sprintf(
      "positron daily_stars has no rows between %s and %s",
      positron_star_dates[gap_i], positron_star_dates[gap_i + 1]
    ),
    q16_visitors_first = fmt(positron_visitors("2024-12-01", "2024-12-31")),
    q16_visitors_last = fmt(positron_visitors("2026-06-01", "2026-06-30")),
    q17_latest_cran = sprintf(
      "latest CRAN day in the data: %s, %s downloads across tracked packages",
      latest_cran$date, fmt(latest_cran$downloads)
    ),
    q18_pairs_ytd = paste(pairs_ytd, collapse = "; "),
    q18_shiny_matched = sprintf(
      "shiny (CRAN) %s vs shiny for python (PyPI) %s since 2025-06-04",
      fmt(shiny_matched$downloads[shiny_matched$project == "shiny-r"]),
      fmt(shiny_matched$downloads[shiny_matched$project == "shiny-python"])
    ),
    q18_matched_totals = sprintf(
      "across all six pairs since 2025-06-04: CRAN %s vs PyPI %s",
      fmt(matched_totals$downloads[matched_totals$source == "cran"]),
      fmt(matched_totals$downloads[matched_totals$source == "pypi"])
    ),
    q19_tags = sprintf(
      "%d of %d projects have language tags; only %d are tagged python",
      tag_stats$n_tagged, tag_stats$n_projects, tag_stats$n_python
    ),
    q19_pypi_roster = paste(pypi_roster$project, collapse = ", "),
    q20_positron_sources = paste(positron_sources$source, collapse = ", "),
    q21_may_videos = sprintf(
      "%d videos were published in May 2026; their current cumulative lifetime views total %s",
      may_videos$n, fmt(may_videos$views)
    ),
    q24_tidyverse_repos = sprintf(
      "%d tidyverse-org repos are tracked: %s",
      nrow(tidyverse_repos), paste(tidyverse_repos$target, collapse = ", ")
    ),
    q26_workflows_target = workflows_target
  )
}

main <- function(mode = c("author", "audit")) {
  mode <- match.arg(mode)
  con <- DBI::dbConnect(duckdb::duckdb(), "data/devrel.duckdb", read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  computed <- compute_targets(con)

  if (mode == "author") {
    yaml::write_yaml(computed, targets_path)
    cli::cli_inform("Wrote {length(computed)} targets to {.path {targets_path}}.")
    return(invisible(computed))
  }

  stored <- yaml::read_yaml(targets_path)
  keys <- union(names(stored), names(computed))
  mismatched <- keys[vapply(
    keys,
    function(k) !identical(as.character(stored[[k]]), as.character(computed[[k]])),
    logical(1)
  )]

  if (length(mismatched)) {
    for (k in mismatched) {
      cli::cli_inform(c(
        "x" = "{.field {k}} drifted:",
        " " = "stored:   {stored[[k]]}",
        " " = "computed: {computed[[k]]}"
      ))
    }
    cli::cli_abort("{length(mismatched)} target{?s} drifted; re-author against the current snapshot.")
  }

  cli::cli_inform("All {length(keys)} targets match the stored file.")
  invisible(computed)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  main(if (length(args)) args[[1]] else "audit")
}
