# Entry point for the devrel agent eval. Run from the project root:
#
#   source("evals/run.R")
#   results <- run_eval()                # full set
#   results <- run_eval(ids = c("q01", "q14", "q26"))   # subset
#
# The solver seam: run_eval() takes a solver factory, so a future arm (e.g.
# Claude Code over the same database) plugs in as a different make_solver.

source("evals/R/dataset.R")
source("evals/R/tools.R")
source("evals/R/agents.R")
source("evals/R/solvers.R")
source("evals/R/scorers.R")
source("evals/R/metrics.R")

run_eval <- function(
  ids = NULL,
  epochs = 1,
  log_dir = "evals/logs",
  name = "devrel-commons",
  make_solver = NULL,
  view = FALSE
) {
  dataset <- load_eval_dataset()
  if (!is.null(ids)) {
    dataset <- dataset[dataset$id %in% ids, , drop = FALSE]
  }

  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  con <- make_devrel_con()
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  if (is.null(make_solver)) {
    make_solver <- function() make_devrel_solver(con)
  }

  task <- vitals::Task$new(
    dataset = dataset,
    solver = make_solver(),
    scorer = make_devrel_scorer(make_grader_client()),
    name = name,
    dir = log_dir
  )

  task$eval(epochs = epochs, view = view)

  samples <- augment_sample_metrics(task$get_samples())

  list(
    task = task,
    samples = samples,
    by_category = summarise_by_category(samples)
  )
}
