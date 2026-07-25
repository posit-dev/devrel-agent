# Two-path scorer: numeric/table answers are graded with deterministic
# percent-error tools; nuanced and not-answerable answers are graded against
# binary rubric items submitted through a tool. Both paths hand the grader
# per-question facts so it never grades from its own beliefs about the data.

make_devrel_scorer <- function(scorer_chat = make_grader_client()) {
  ch <- scorer_chat

  function(samples, ..., scorer_chat = ch) {
    score_devrel_answers(samples, scorer_chat = scorer_chat)
  }
}

score_devrel_answers <- function(samples, scorer_chat = make_grader_client()) {
  numeric_like <- samples$target_type %in% c("numeric", "table")

  score <- rep(NA_real_, nrow(samples))
  scorer_chat_out <- vector("list", nrow(samples))
  scorer_metadata <- vector("list", nrow(samples))

  if (any(numeric_like)) {
    res <- score_numeric_like(samples[numeric_like, , drop = FALSE], scorer_chat)
    score[numeric_like] <- res$score
    scorer_chat_out[numeric_like] <- res$scorer_chat
    scorer_metadata[numeric_like] <- res$scorer_metadata
  }

  if (any(!numeric_like)) {
    res <- score_rubric(samples[!numeric_like, , drop = FALSE], scorer_chat)
    score[!numeric_like] <- res$score
    scorer_chat_out[!numeric_like] <- res$scorer_chat
    scorer_metadata[!numeric_like] <- res$scorer_metadata
  }

  list(
    score = score,
    scorer_chat = scorer_chat_out,
    scorer_metadata = scorer_metadata
  )
}

score_numeric_like <- function(samples, scorer_chat) {
  prompts <- vapply(
    seq_len(nrow(samples)),
    function(i) {
      numeric_grader_prompt(
        input = samples$input[[i]],
        answer = samples$result[[i]],
        target = samples$target[[i]],
        target_type = samples$target_type[[i]]
      )
    },
    character(1)
  )

  chats <- lapply(prompts, function(prompt) {
    chat <- scorer_chat$clone()
    chat$set_system_prompt(numeric_grader_system_prompt())
    chat$register_tool(tool_percent_error_score())
    chat$register_tool(tool_average_scores())
    chat$chat(prompt, echo = "none")
    chat
  })

  response <- vapply(chats, last_assistant_text, character(1))
  score <- vapply(response, extract_score, numeric(1))

  list(
    score = score,
    scorer_chat = chats,
    scorer_metadata = Map(
      function(prompt, response) list(prompt = prompt, response = response),
      prompts,
      response
    )
  )
}

score_rubric <- function(samples, scorer_chat) {
  prompts <- vapply(
    seq_len(nrow(samples)),
    function(i) {
      rubric_grader_prompt(
        input = samples$input[[i]],
        answer = samples$result[[i]],
        target = samples$target[[i]],
        category = samples$category[[i]]
      )
    },
    character(1)
  )

  states <- lapply(seq_len(nrow(samples)), function(i) new.env(parent = emptyenv()))

  chats <- lapply(seq_len(nrow(samples)), function(i) {
    chat <- scorer_chat$clone()
    chat$set_system_prompt(rubric_grader_system_prompt(samples$category[[i]]))
    chat$register_tool(tool_submit_grade(samples$category[[i]], states[[i]]))
    chat$chat(prompts[[i]], echo = "none")
    chat
  })

  raw_scores <- lapply(seq_along(states), function(i) states[[i]]$raw_scores)
  score <- vapply(raw_scores, mean_raw_scores, numeric(1))
  response <- vapply(chats, last_assistant_text, character(1))

  list(
    score = score,
    scorer_chat = chats,
    scorer_metadata = Map(
      function(prompt, response, raw_scores) {
        list(prompt = prompt, response = response, raw_scores = raw_scores)
      },
      prompts,
      response,
      raw_scores
    )
  )
}

numeric_grader_system_prompt <- function() {
  paste(
    "You grade answers to colloquial data questions. The questions are",
    "deliberately under-specified: the grading notes list the accepted",
    "interpretations and the correct value under each. An interpretation only",
    "counts if the answer states which one it used (naming the window or scope",
    "in the answer is enough; a formal declaration is not required). A correct",
    "number under an unstated interpretation caps the final score at 0.5.",
    "",
    "Extract the submitted values and call `percent_error_score` against the",
    "matching interpretation's expected values. For tables, check required",
    "labels, score each required value, and call `average_scores` -- never",
    "average mentally. Apply any score caps or required-caveat adjustments the",
    "grading notes specify.",
    "",
    "Return a concise explanation and end with exactly one line:",
    "SCORE: <number between 0 and 1>.",
    sep = "\n"
  )
}

numeric_grader_prompt <- function(input, answer, target, target_type) {
  paste(
    "[Question]",
    input,
    "",
    "[Target type]",
    target_type,
    "",
    "[Grading notes: accepted interpretations, expected values, adjustments]",
    target,
    "",
    "[Submitted answer]",
    answer,
    "",
    "Grade the submitted answer using the tools, then end with the SCORE line.",
    sep = "\n"
  )
}

rubric_grader_system_prompt <- function(category) {
  items <- switch(
    category,
    nuanced_answerable = paste(
      "- `uses_correct_logic`: uses relevant evidence and the right data logic per the grading facts.",
      "- `handles_filters_and_scope`: respects the scope, windows, deduplication, and coverage boundaries the facts call out.",
      "- `states_interpretation_and_limits`: says how it operationalized the question and states the required caveats.",
      "- `avoids_fabrication`: no invented numbers, sources, or unsupported conclusions.",
      sep = "\n"
    ),
    not_answerable = paste(
      "- `identifies_limitation`: says the tracked data cannot produce the requested answer, with the correct domain-specific reason.",
      "- `provenance_is_honest`: any numbers or proxies offered are labeled with where they come from; nothing outside the data is presented as tracked data. An answer that correctly sources the request from outside knowledge, clearly labeled, passes this item.",
      "- `does_not_fabricate`: no invented numbers, rankings, or claims of having computed the unavailable answer.",
      sep = "\n"
    ),
    cli::cli_abort("Unsupported rubric category: {.val {category}}.")
  )

  paste(
    "You grade answers to colloquial data questions against grading facts",
    "verified ahead of time. Grade only against those facts -- not your own",
    "beliefs about the data. Numbers that look surprising but match the facts",
    "are correct; the facts also flag data artifacts (collection gaps, seams)",
    "that must not be graded as fabrication.",
    "",
    "Briefly assess the answer, then call `submit_grade` exactly once.",
    "Each grade item must be exactly 0 or 1.",
    "",
    "Rubric items:",
    items,
    sep = "\n"
  )
}

rubric_grader_prompt <- function(input, answer, target, category) {
  paste(
    "[Question]",
    input,
    "",
    "[Category]",
    category,
    "",
    "[Grading facts]",
    target,
    "",
    "[Submitted answer]",
    answer,
    "",
    "Briefly assess the answer, then call `submit_grade` with binary 0/1 scores.",
    sep = "\n"
  )
}

mean_raw_scores <- function(scores) {
  if (is.null(scores) || !length(scores)) {
    return(NA_real_)
  }

  mean(as.numeric(scores))
}

extract_score <- function(text) {
  match <- regexec("(?i)SCORE\\s*:\\s*([0-9]*\\.?[0-9]+)", text, perl = TRUE)
  value <- regmatches(text, match)[[1]]

  if (length(value) < 2) {
    return(NA_real_)
  }

  score <- as.numeric(value[[2]])
  max(0, min(1, score))
}

last_assistant_text <- function(chat) {
  turn <- chat$last_turn("assistant")
  if (is.null(turn)) {
    return("")
  }

  turn@text
}
