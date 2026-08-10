eval_logs <- c(
  "devrel-agent" = "evals/logs/2026-08-10T13-46-57-05-00_devrel-commons-sonnet5-medium-claude-sonnet-5-343b8116a73272e07b957f.json",
  "Claude Code" = "evals/logs/2026-08-10T14-31-54-05-00_devrel-commons-claude-code-closed-book-sonnet5-medium-claude-sonnet-5-343b8116a73272e07b957f.json"
)

estimate_run_variability <- function(
  logs = eval_logs,
  simulations = 100000L,
  interval_mass = 0.95,
  seed = 20260810L
) {
  if (length(logs) != 2L || is.null(names(logs)) || any(names(logs) == "")) {
    cli::cli_abort("{.arg logs} must name exactly two eval log paths.")
  }
  if (simulations < 1L || simulations != as.integer(simulations)) {
    cli::cli_abort("{.arg simulations} must be a positive integer.")
  }
  if (interval_mass <= 0 || interval_mass >= 1) {
    cli::cli_abort("{.arg interval_mass} must be between zero and one.")
  }

  scores <- Map(read_eval_scores, unname(logs), names(logs))
  names(scores) <- names(logs)
  score_matrices <- lapply(scores, scores_to_matrix)
  score_matrices <- align_score_matrices(score_matrices)

  set.seed(seed)
  draws <- vapply(
    score_matrices,
    simulate_runs,
    numeric(simulations),
    simulations = simulations
  )

  list(
    method = paste(
      "Each simulated run independently selects one observed epoch score",
      "for every question and agent, holding the question set fixed."
    ),
    limitation = paste(
      "With only two epochs, these are empirical sensitivity intervals,",
      "not calibrated confidence intervals for future runs."
    ),
    observed_epochs = summarise_observed_epochs(score_matrices),
    agents = summarise_run_draws(score_matrices, draws, interval_mass),
    comparison = summarise_run_difference(score_matrices, draws, interval_mass),
    draws = draws
  )
}

print_run_variability <- function(results) {
  cat(results$method, "\n", results$limitation, "\n\n", sep = "")
  cat("Observed epochs\n")
  print(tibble::as_tibble(results$observed_epochs), n = Inf, width = Inf)
  cat("\nSimulated run variability\n")
  print(tibble::as_tibble(results$agents), n = Inf, width = Inf)
  cat("\nAgent difference\n")
  print(tibble::as_tibble(results$comparison), n = Inf, width = Inf)
  invisible(results)
}

read_eval_scores <- function(log_path, agent, call = rlang::caller_env()) {
  if (!file.exists(log_path)) {
    cli::cli_abort("Eval log {.path {log_path}} does not exist.", call = call)
  }

  samples <- jsonlite::read_json(log_path, simplifyVector = FALSE)$samples
  scores <- data.frame(
    agent = agent,
    id = vapply(samples, `[[`, character(1), "id"),
    epoch = vapply(samples, `[[`, numeric(1), "epoch"),
    score = vapply(samples, sample_score, numeric(1))
  )

  if (any(!is.finite(scores$score)) || any(scores$score < 0 | scores$score > 1)) {
    cli::cli_abort(
      "All scores in {.path {log_path}} must be numeric values between zero and one.",
      call = call
    )
  }
  if (anyDuplicated(scores[c("id", "epoch")])) {
    cli::cli_abort(
      "Eval log {.path {log_path}} has duplicate question and epoch pairs.",
      call = call
    )
  }

  scores
}

sample_score <- function(sample) {
  as.numeric(unname(sample$scores)[[1]]$value)
}

scores_to_matrix <- function(scores, call = rlang::caller_env()) {
  question_ids <- unique(scores$id)
  epochs <- sort(unique(scores$epoch))
  score_matrix <- matrix(
    NA_real_,
    nrow = length(question_ids),
    ncol = length(epochs),
    dimnames = list(question_ids, paste0("epoch_", epochs))
  )
  score_matrix[cbind(match(scores$id, question_ids), match(scores$epoch, epochs))] <- scores$score

  if (ncol(score_matrix) < 2L) {
    cli::cli_abort(
      "Run variability requires at least two epochs for each agent.",
      call = call
    )
  }
  if (anyNA(score_matrix)) {
    cli::cli_abort(
      "Every question must have a score in every epoch.",
      call = call
    )
  }

  score_matrix
}

align_score_matrices <- function(score_matrices, call = rlang::caller_env()) {
  reference_ids <- rownames(score_matrices[[1]])
  same_questions <- vapply(
    score_matrices,
    function(score_matrix) setequal(rownames(score_matrix), reference_ids),
    logical(1)
  )
  if (!all(same_questions)) {
    cli::cli_abort("The eval logs must contain the same questions.", call = call)
  }

  lapply(score_matrices, function(score_matrix) {
    score_matrix[reference_ids, , drop = FALSE]
  })
}

simulate_runs <- function(score_matrix, simulations) {
  questions <- nrow(score_matrix)
  selected_epochs <- matrix(
    sample.int(ncol(score_matrix), questions * simulations, replace = TRUE),
    nrow = questions
  )
  selected_scores <- score_matrix[cbind(
    rep(seq_len(questions), simulations),
    as.vector(selected_epochs)
  )]
  colMeans(matrix(selected_scores, nrow = questions))
}

summarise_observed_epochs <- function(score_matrices) {
  summaries <- Map(observed_epoch_summary, score_matrices, names(score_matrices))
  do.call(rbind, summaries)
}

observed_epoch_summary <- function(score_matrix, agent) {
  data.frame(
    agent = agent,
    epoch = seq_len(ncol(score_matrix)),
    accuracy_pct = 100 * colMeans(score_matrix),
    row.names = NULL
  )
}

summarise_run_draws <- function(score_matrices, draws, interval_mass) {
  interval <- interval_probabilities(interval_mass)
  data.frame(
    agent = names(score_matrices),
    mean_accuracy_pct = 100 * vapply(score_matrices, mean, numeric(1)),
    run_sd_points = 100 * apply(draws, 2, stats::sd),
    run_lower_pct = 100 * apply(draws, 2, stats::quantile, probs = interval[[1]]),
    run_upper_pct = 100 * apply(draws, 2, stats::quantile, probs = interval[[2]]),
    row.names = NULL
  )
}

summarise_run_difference <- function(score_matrices, draws, interval_mass) {
  interval <- interval_probabilities(interval_mass)
  difference_draws <- draws[, 1] - draws[, 2]
  observed_difference <- mean(score_matrices[[1]]) - mean(score_matrices[[2]])

  data.frame(
    comparison = paste(names(score_matrices), collapse = " minus "),
    mean_difference_points = 100 * observed_difference,
    run_sd_points = 100 * stats::sd(difference_draws),
    run_lower_points = 100 * stats::quantile(difference_draws, interval[[1]]),
    run_upper_points = 100 * stats::quantile(difference_draws, interval[[2]]),
    share_simulations_first_higher = mean(difference_draws > 0),
    row.names = NULL
  )
}

interval_probabilities <- function(interval_mass) {
  alpha <- 1 - interval_mass
  c(alpha / 2, 1 - alpha / 2)
}

run_variability <- estimate_run_variability()
print_run_variability(run_variability)
