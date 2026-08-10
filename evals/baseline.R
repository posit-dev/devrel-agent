# One full baseline run: Sonnet 5 with adaptive thinking at high effort.
# Run from the project root:
#
#   Rscript evals/baseline.R
#
# Logs land in evals/logs/ as vitals JSON.

source("evals/run.R")

results <- run_eval(
  name = "devrel-commons-sonnet5-high"
)

cols <- c("id", "category", "score", "latency_sec", "input_tokens", "output_tokens")
print(as.data.frame(results$samples[, cols]))
cat("\n")
print(as.data.frame(results$by_category))
