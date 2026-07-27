# One closed-book Claude Code run over the same 26 questions as the commons
# baseline: Sonnet 5 in a container holding a clone of posit-dev/devrel-io.
# Run from the project root:
#
#   Rscript evals/claude-code.R
#
# Logs land in evals/logs/ as vitals JSON. The first run also builds the
# sandbox image and downloads the Claude Code CLI into it.

source("evals/run.R")

results <- run_eval(
  name = "devrel-commons-claude-code-closed-book",
  make_solver = make_claude_code_solver
)

cols <- c("id", "category", "score", "latency_sec", "input_tokens", "output_tokens")
print(as.data.frame(results$samples[, cols]))
cat("\n")
print(as.data.frame(results$by_category))
