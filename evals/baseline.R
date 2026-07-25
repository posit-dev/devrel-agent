# One full baseline run: Sonnet 5 with adaptive thinking at medium effort.
# Run from the project root:
#
#   Rscript evals/baseline.R
#
# Logs land in evals/logs/ as vitals JSON.

source("evals/run.R")

sonnet5_medium <- function() {
  ellmer::chat_anthropic(
    model = "claude-sonnet-5",
    api_args = list(
      thinking = list(type = "adaptive"),
      output_config = list(effort = "medium")
    )
  )
}

results <- run_eval(
  name = "devrel-commons-sonnet5-medium",
  solver_client = sonnet5_medium
)

cols <- c("id", "category", "score", "latency_sec", "input_tokens", "output_tokens")
print(as.data.frame(results$samples[, cols]))
cat("\n")
print(as.data.frame(results$by_category))
