source("evals/R/metrics.R")

log_files <- commandArgs(trailingOnly = TRUE)
if (!length(log_files)) {
  log_files <- tail(sort(list.files(
    "evals/logs",
    pattern = "\\.json$",
    full.names = TRUE
  )), 2)
}

systems <- ifelse(
  grepl("claude-code-closed-book", log_files, fixed = TRUE),
  "Claude Code",
  "commons"
)
if (!setequal(systems, c("Claude Code", "commons"))) {
  cli::cli_abort("Expected one Claude Code run and one commons run.")
}

results <- Map(function(file, system) {
  samples <- augment_sample_metrics(vitals::vitals_log_read(file))
  samples$system <- system
  samples
}, log_files, systems) |>
  dplyr::bind_rows()

results$solver_chat <- NULL
results$scorer_chat <- NULL
sonnet5_price_per_mtok <- c(input = 2, cached_input = 0.2, output = 10)
results$cost_usd <- (
  results$input_tokens * sonnet5_price_per_mtok["input"] +
    results$cached_input_tokens * sonnet5_price_per_mtok["cached_input"] +
    results$output_tokens * sonnet5_price_per_mtok["output"]
) / 1e6

utils::write.csv(results, "evals/results.csv", row.names = FALSE, na = "")
