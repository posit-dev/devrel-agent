# Deterministic scoring tools for the LLM grader. The grader extracts values
# from prose but must delegate all arithmetic to these tools.

percent_error_score <- function(actual, expected) {
  if (expected == 0) {
    return(if (actual == 0) 1 else 0)
  }

  pct_error <- abs(actual - expected) / abs(expected)
  max(0, 1 - pct_error)
}

average_scores <- function(scores) {
  scores <- as.numeric(scores)
  scores <- scores[!is.na(scores)]

  if (!length(scores)) {
    cli::cli_abort("At least one score is required.")
  }

  mean(pmin(1, pmax(0, scores)))
}

tool_percent_error_score <- function() {
  ellmer::tool(
    percent_error_score,
    "Calculate a 0-1 score from percent error. 1 is exact; 0.5 is 50% error; 0 is 100% or more error.",
    arguments = list(
      actual = ellmer::type_number("The numeric value in the submitted answer."),
      expected = ellmer::type_number("The numeric value in the target answer.")
    ),
    name = "percent_error_score",
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
}

tool_average_scores <- function() {
  ellmer::tool(
    average_scores,
    "Average one or more 0-1 scores. Use this after scoring table cells with percent_error_score.",
    arguments = list(
      scores = ellmer::type_array(
        ellmer::type_number("A 0-1 score."),
        "Scores to average."
      )
    ),
    name = "average_scores",
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
}

tool_submit_grade <- function(category, state) {
  switch(
    category,
    nuanced_answerable = tool_submit_nuanced_grade(state),
    not_answerable = tool_submit_not_answerable_grade(state),
    cli::cli_abort("Unsupported rubric category: {.val {category}}.")
  )
}

tool_submit_nuanced_grade <- function(state) {
  ellmer::tool(
    function(
      uses_correct_logic,
      handles_filters_and_scope,
      states_interpretation_and_limits,
      avoids_fabrication
    ) {
      scores <- validate_binary_scores(
        list(
          uses_correct_logic = uses_correct_logic,
          handles_filters_and_scope = handles_filters_and_scope,
          states_interpretation_and_limits = states_interpretation_and_limits,
          avoids_fabrication = avoids_fabrication
        )
      )
      state$raw_scores <- scores
      as.list(scores)
    },
    "Submit binary rubric scores for a nuanced answerable question.",
    arguments = list(
      uses_correct_logic = ellmer::type_integer(
        "1 if the answer uses relevant evidence and correct data logic per the grading facts; otherwise 0."
      ),
      handles_filters_and_scope = ellmer::type_integer(
        "1 if the answer handles the scope, windows, deduplication, and coverage boundaries the grading facts require; otherwise 0."
      ),
      states_interpretation_and_limits = ellmer::type_integer(
        "1 if the answer states how it operationalized the question and the required caveats or limits; otherwise 0."
      ),
      avoids_fabrication = ellmer::type_integer(
        "1 if the answer avoids invented numbers, sources, or unsupported conclusions; otherwise 0."
      )
    ),
    name = "submit_grade",
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
}

tool_submit_not_answerable_grade <- function(state) {
  ellmer::tool(
    function(identifies_limitation, provenance_is_honest, does_not_fabricate) {
      scores <- validate_binary_scores(
        list(
          identifies_limitation = identifies_limitation,
          provenance_is_honest = provenance_is_honest,
          does_not_fabricate = does_not_fabricate
        )
      )
      state$raw_scores <- scores
      as.list(scores)
    },
    "Submit binary rubric scores for a not-answerable question.",
    arguments = list(
      identifies_limitation = ellmer::type_integer(
        "1 if the answer says the tracked data cannot produce the requested answer, with the correct domain-specific reason; otherwise 0."
      ),
      provenance_is_honest = ellmer::type_integer(
        "1 if every number or proxy offered is labeled with where it comes from and nothing outside the data is presented as tracked data; otherwise 0."
      ),
      does_not_fabricate = ellmer::type_integer(
        "1 if the answer does not invent numbers, rankings, or claims of having computed the unavailable answer; otherwise 0."
      )
    ),
    name = "submit_grade",
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
}

validate_binary_scores <- function(scores, call = rlang::caller_env()) {
  nms <- names(scores)
  scores <- as.integer(unlist(scores, use.names = FALSE))

  if (any(is.na(scores)) || any(!scores %in% c(0L, 1L))) {
    cli::cli_abort("Rubric scores must be binary 0/1 values.", call = call)
  }

  names(scores) <- nms
  scores
}
