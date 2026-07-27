# Per-sample cost and latency, read back off the solver chats.

sample_latency_sec <- function(chat) {
  turns <- chat$get_turns()
  assistant <- turns[vapply(turns, inherits, logical(1), "ellmer::AssistantTurn")]

  if (!length(assistant)) {
    return(NA_real_)
  }

  durations <- vapply(assistant, function(turn) turn@duration, numeric(1))
  if (all(is.na(durations))) {
    return(NA_real_)
  }

  sum(durations, na.rm = TRUE)
}

# ellmer has no price entry for some model ids, so cost can be NA even when
# token counts are present; record both.
sample_cost_usd <- function(chat) {
  as.numeric(chat$get_cost())
}

sample_tokens <- function(chat, column) {
  tokens <- chat$get_tokens()
  if (!nrow(tokens)) {
    return(NA_real_)
  }
  sum(tokens[[column]], na.rm = TRUE)
}

# Agent solvers call the model inside a sandbox rather than through ellmer, so
# their reconstructed chats under-count; `model_usage` is the real tally.
metadata_tokens <- function(metadata, field) {
  usage <- metadata$model_usage
  if (is.null(usage)) {
    return(NA_real_)
  }
  sum(vapply(usage, function(x) as.numeric(x[[field]] %||% 0), numeric(1)))
}

augment_sample_metrics <- function(samples) {
  samples$latency_sec <- vapply(samples$solver_chat, sample_latency_sec, numeric(1))
  samples$cost_usd <- vapply(samples$solver_chat, sample_cost_usd, numeric(1))
  samples$input_tokens <- sample_token_column(samples, "input", "input_tokens")
  samples$cached_input_tokens <- sample_token_column(
    samples,
    "cached_input",
    "input_tokens_cache_read"
  )
  samples$output_tokens <- sample_token_column(samples, "output", "output_tokens")
  samples
}

sample_token_column <- function(samples, chat_column, usage_field) {
  from_chat <- vapply(samples$solver_chat, sample_tokens, numeric(1), column = chat_column)
  metadata <- samples$solver_metadata
  if (is.null(metadata)) {
    return(from_chat)
  }

  from_usage <- vapply(metadata, metadata_tokens, numeric(1), field = usage_field)
  ifelse(is.na(from_usage), from_chat, from_usage)
}

summarise_by_category <- function(samples) {
  samples |>
    dplyr::group_by(.data$category) |>
    dplyr::summarise(
      n = dplyr::n(),
      accuracy = mean(.data$score, na.rm = TRUE),
      median_latency_sec = stats::median(.data$latency_sec, na.rm = TRUE),
      mean_input_tokens = mean(.data$input_tokens, na.rm = TRUE),
      mean_output_tokens = mean(.data$output_tokens, na.rm = TRUE),
      mean_cost_usd = mean(.data$cost_usd, na.rm = TRUE),
      .groups = "drop"
    )
}
