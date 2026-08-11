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
  digests <- trajectory_digests(samples)
  prompts <- vapply(
    seq_len(nrow(samples)),
    function(i) {
      numeric_grader_prompt(
        input = samples$input[[i]],
        answer = samples$result[[i]],
        target = samples$target[[i]],
        target_type = samples$target_type[[i]],
        trajectory = digests[[i]]
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

  response <- vapply(chats, grader_response_text, character(1))
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
  digests <- trajectory_digests(samples)
  prompts <- vapply(
    seq_len(nrow(samples)),
    function(i) {
      rubric_grader_prompt(
        input = samples$input[[i]],
        answer = samples$result[[i]],
        target = samples$target[[i]],
        category = samples$category[[i]],
        trajectory = digests[[i]]
      )
    },
    character(1)
  )

  grades <- Map(
    grade_rubric_sample,
    prompts,
    samples$category,
    MoreArgs = list(scorer_chat = scorer_chat)
  )

  chats <- lapply(grades, `[[`, "chat")
  raw_scores <- lapply(grades, `[[`, "raw_scores")
  item_reasons <- lapply(grades, `[[`, "item_reasons")
  score <- vapply(raw_scores, mean_raw_scores, numeric(1))
  response <- vapply(chats, grader_response_text, character(1))

  list(
    score = score,
    scorer_chat = chats,
    scorer_metadata = Map(
      function(prompt, response, raw_scores, item_reasons) {
        list(
          prompt = prompt,
          response = response,
          raw_scores = raw_scores,
          item_reasons = item_reasons
        )
      },
      prompts,
      response,
      raw_scores,
      item_reasons
    )
  )
}

grade_rubric_sample <- function(
  prompt,
  category,
  scorer_chat,
  max_attempts = 2L,
  call = rlang::caller_env()
) {
  state <- new.env(parent = emptyenv())
  chat <- scorer_chat$clone()
  chat$set_system_prompt(rubric_grader_system_prompt(category))
  chat$register_tool(tool_submit_grade(category, state))

  for (attempt in seq_len(max_attempts)) {
    current_prompt <- if (attempt == 1L) {
      prompt
    } else {
      "Call `submit_grade` now with the required binary scores and reasons. Do not provide more prose."
    }
    chat$chat(current_prompt, echo = "none")

    if (!is.null(state$raw_scores)) {
      return(list(
        chat = chat,
        raw_scores = state$raw_scores,
        item_reasons = state$item_reasons
      ))
    }
  }

  cli::cli_abort(
    "The rubric grader did not submit a grade after {max_attempts} attempts.",
    call = call
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
    "The prompt includes the solver's tool trajectory (its queries and full",
    "results). Use it only to establish where the answer's numbers",
    "came from and what was actually queried -- e.g. whether a value reflects",
    "a stated alternative window, or a missing filter the grading notes warn",
    "about. The grading notes remain the ground truth for expected values, and",
    "the interpretation must be stated in the answer itself, not merely",
    "visible in a query.",
    "",
    "Extract the submitted values and call `percent_error_score` against the",
    "matching interpretation's expected values. For tables, check required",
    "labels, score each required value, and call `average_scores` -- never",
    "average mentally. Apply any score caps or required-caveat adjustments the",
    "grading notes specify.",
    "`Target type` describes the grading structure, not the requested answer",
    "format. Do not deduct for prose instead of a table unless the grading",
    "notes explicitly require a format.",
    "",
    "Return a concise explanation and end with exactly one line:",
    "SCORE: <number between 0 and 1>.",
    sep = "\n"
  )
}

numeric_grader_prompt <- function(input, answer, target, target_type, trajectory) {
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
    "[Solver tool trajectory: provenance only; full results]",
    trajectory,
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
    "The grading facts are a verified subset of the database, not an",
    "inventory of it. The prompt includes the solver's tool trajectory (its",
    "queries and full results); use it to establish provenance. A value,",
    "name, or schema term absent from the facts but visible in the",
    "trajectory's queries or results is unverified-but-real, not fabricated.",
    "Fail a fabrication item only on positive evidence: a value that",
    "contradicts the facts under the same stated scope, a claim of having",
    "computed something the facts say is unavailable, or an attribution the",
    "facts explicitly identify as wrong. A true caveat or mechanism the facts",
    "don't mention is not an error.",
    "",
    "Items about what the answer states (interpretations, caveats,",
    "limitations) are judged on the final answer text alone -- the user never",
    "sees the trajectory. Each item is scored against its own criterion: an",
    "answer can be wrong in one claim and still earn the items that claim",
    "doesn't touch, and one flaw zeroes multiple items only when each item's",
    "criterion is independently violated. When an item's reason asserts",
    "something the solver did or didn't do, it must point to the specific",
    "query or result in the trajectory; before asserting the answer misused",
    "or mislabeled a metric, check that the grading facts actually contradict",
    "the answer's usage.",
    "",
    "Assess the answer item by item, then call `submit_grade` exactly once,",
    "with each item's reason addressing that item's criterion alone.",
    "Each grade item must be exactly 0 or 1.",
    "",
    "Rubric items:",
    items,
    sep = "\n"
  )
}

rubric_grader_prompt <- function(input, answer, target, category, trajectory) {
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
    "[Solver tool trajectory: provenance only; full results]",
    trajectory,
    "",
    "[Submitted answer]",
    answer,
    "",
    "Assess the answer item by item, then call `submit_grade` with binary 0/1 scores.",
    sep = "\n"
  )
}

# The grader sees the solver's tool trajectory so provenance is checkable:
# numbers from a real query under a stated alternative scope must not grade
# as fabricated, and a query's actual scope (e.g. a missing dedup filter) is
# visible.
trajectory_digests <- function(samples) {
  chats <- samples$solver_chat
  if (is.null(chats)) {
    return(rep(list("(solver trajectory unavailable)"), nrow(samples)))
  }
  lapply(chats, solver_trajectory_digest)
}

solver_trajectory_digest <- function(chat) {
  if (is.null(chat)) {
    return("(solver trajectory unavailable)")
  }

  lines <- character()
  for (turn in chat$get_turns()) {
    for (content in turn@contents) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        args <- tryCatch(
          jsonlite::toJSON(content@arguments, auto_unbox = TRUE),
          error = function(e) "<arguments unavailable>"
        )
        lines <- c(lines, paste0("TOOL CALL ", content@name, ": ", args))
      } else if (inherits(content, "ellmer::ContentToolResult")) {
        result <- tool_result_text(content)
        lines <- c(lines, paste0("RESULT: ", result), "")
      }
    }
  }

  if (!length(lines)) {
    return("(the solver made no tool calls)")
  }
  paste(lines, collapse = "\n")
}

tool_result_text <- function(result) {
  error <- tryCatch(result@error, error = function(e) NULL)
  if (!is.null(error)) {
    return(paste0("<tool error: ", paste(format(error), collapse = " "), ">"))
  }
  strip_solver_instructions(value_text(result@value))
}

strip_solver_instructions <- function(text) {
  sub(
    "\\nNote: any answer in this conversation that does not come from a trusted calculation alone[\\s\\S]*$",
    "",
    text,
    perl = TRUE
  )
}

# Tool results are not always strings: commons tools can return ellmer
# Content objects (text, images from run_r plots) or lists of them.
value_text <- function(value) {
  if (is.character(value)) {
    return(paste(value, collapse = "\n"))
  }
  if (inherits(value, "ellmer::Content")) {
    text <- tryCatch(ellmer::contents_text(value), error = function(e) NA_character_)
    if (length(text) == 1 && !is.na(text) && nzchar(text)) {
      return(text)
    }
    return(paste0("<", class(value)[[1]], ">"))
  }
  if (is.list(value)) {
    return(paste(vapply(value, value_text, character(1)), collapse = "\n"))
  }
  tryCatch(
    paste(format(value), collapse = "\n"),
    error = function(e) paste0("<", class(value)[[1]], ">")
  )
}

mean_raw_scores <- function(scores) {
  if (is.null(scores) || !length(scores)) {
    return(NA_real_)
  }

  mean(as.numeric(scores))
}

# Take the last match: grader arithmetic like "Final score: 0.9999 x 0.9"
# earlier in the reply must not shadow the terminal SCORE line.
extract_score <- function(text) {
  matches <- regmatches(
    text,
    gregexpr("(?i)score\\s*:\\s*([0-9]*\\.?[0-9]+)", text, perl = TRUE)
  )[[1]]

  if (!length(matches)) {
    return(NA_real_)
  }

  score <- as.numeric(sub("(?i).*score\\s*:\\s*", "", matches[[length(matches)]], perl = TRUE))
  max(0, min(1, score))
}

grader_response_text <- function(chat) {
  turns <- chat$get_turns()
  texts <- vapply(
    turns,
    function(turn) {
      if (inherits(turn, "ellmer::AssistantTurn")) turn@text else ""
    },
    character(1)
  )
  paste(texts[nzchar(texts)], collapse = "\n\n")
}

last_assistant_text <- function(chat) {
  turn <- chat$last_turn("assistant")
  if (is.null(turn)) {
    return("")
  }

  turn@text
}
