# Loads evals/questions.yaml and interpolates stored and runtime grading facts,
# so targets stay machine-derived while question prose stays hand-authored.

load_eval_dataset <- function(
  questions_path = "evals/questions.yaml",
  targets_path = "evals/targets.yaml",
  current_date = Sys.Date()
) {
  questions <- yaml::read_yaml(questions_path)
  targets <- yaml::read_yaml(targets_path)
  targets <- add_runtime_targets(targets, current_date)

  dataset <- tibble::tibble(
    id = vapply(questions, function(x) x$id, character(1)),
    category = vapply(questions, function(x) x$category, character(1)),
    target_type = vapply(questions, function(x) x$target_type, character(1)),
    input = vapply(questions, function(x) x$input, character(1)),
    target = vapply(
      questions,
      function(x) interpolate_target(x$target, targets, id = x$id),
      character(1)
    )
  )

  validate_eval_dataset(dataset)
  dataset
}

add_runtime_targets <- function(targets, current_date, call = rlang::caller_env()) {
  current_date <- as.Date(current_date)
  if (length(current_date) != 1 || is.na(current_date)) {
    cli::cli_abort("{.arg current_date} must be one valid date.", call = call)
  }

  yesterday <- current_date - 1
  latest_cran_date <- as.Date(targets$q17_latest_cran_date)
  if (
    length(latest_cran_date) != 1 ||
      is.na(latest_cran_date) ||
      latest_cran_date > yesterday
  ) {
    cli::cli_abort(
      "The latest CRAN target date must be on or before yesterday.",
      call = call
    )
  }

  q17_coverage <- if (latest_cran_date == yesterday) {
    sprintf(
      "CRAN data is available for that date: %s downloads across the tracked packages.",
      targets$q17_latest_cran_downloads
    )
  } else {
    sprintf(
      paste(
        "No CRAN data is available for that date.",
        "The latest available CRAN day is %s, with %s downloads across the tracked packages."
      ),
      latest_cran_date,
      targets$q17_latest_cran_downloads
    )
  }

  c(
    targets,
    list(
      eval_current_date = as.character(current_date),
      eval_yesterday = as.character(yesterday),
      q17_coverage = q17_coverage
    )
  )
}

interpolate_target <- function(text, targets, id, call = rlang::caller_env()) {
  out <- glue::glue_data(targets, text, .trim = FALSE)

  leftover <- regmatches(out, gregexpr("\\{[a-z0-9_]+\\}", out))[[1]]
  if (length(leftover)) {
    cli::cli_abort(
      "Question {.val {id}} references missing target{?s}: {.field {leftover}}.",
      call = call
    )
  }

  as.character(out)
}

validate_eval_dataset <- function(dataset, call = rlang::caller_env()) {
  duplicated_ids <- dataset$id[duplicated(dataset$id)]
  if (length(duplicated_ids)) {
    cli::cli_abort("Duplicate question ids: {.val {unique(duplicated_ids)}}.", call = call)
  }

  bad_category <- setdiff(
    unique(dataset$category),
    c("numeric", "nuanced_answerable", "not_answerable")
  )
  if (length(bad_category)) {
    cli::cli_abort("Unsupported categor{?y/ies}: {.val {bad_category}}.", call = call)
  }

  numeric_like <- dataset$target_type %in% c("numeric", "table")
  if (any(numeric_like != (dataset$category == "numeric"))) {
    cli::cli_abort(
      "target_type numeric/table must pair with category numeric (and rubric with the others).",
      call = call
    )
  }

  invisible(dataset)
}
