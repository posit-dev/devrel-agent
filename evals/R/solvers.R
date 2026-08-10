# The commons solver runs samples sequentially, one fresh agent per question
# so sessions share no conversation, handles, or worker state. The async chat
# path is required: the agent's run_r tool is async and aborts ellmer's sync
# `$chat()` whenever the model calls it.

make_devrel_solver <- function(con, client_factory = make_solver_client) {
  force(con)
  force(client_factory)

  function(inputs, ...) {
    inputs <- as.list(inputs)
    chats <- vector("list", length(inputs))

    for (i in seq_along(inputs)) {
      agent <- build_devrel_agent(con, client_factory())
      outcome <- try(run_chat_async(agent, inputs[[i]]), silent = TRUE)

      chats[[i]] <- if (inherits(outcome, "try-error")) {
        failure_chat(client_factory(), inputs[[i]], attr(outcome, "condition"))
      } else {
        agent
      }
    }

    list(
      result = vapply(
        chats,
        function(chat) strip_citations(last_assistant_text(chat)),
        character(1)
      ),
      solver_chat = chats
    )
  }
}

# The comparison arm: Claude Code answering the same questions from a clone of
# posit-dev/devrel-io, with no data dictionary, no registered measures, and no
# crawled site prose. Closed-book -- the repo is the only permitted source --
# so the arms differ in the semantic layer, not in the data they can reach.
make_claude_code_solver <- function(
  solver_chat = make_solver_client,
  compose = "evals/sandbox/compose.yaml",
  time_limit = 1200,
  max_samples = 4
) {
  chat_factory <- function() {
    chat <- solver_chat()
    chat$set_system_prompt(closed_book_system_prompt())
    chat
  }

  vitals::claude_code(
    chat_factory,
    sandbox = c("docker", compose),
    disallowed_tools = closed_book_disallowed_tools(),
    time_limit = time_limit,
    max_samples = max_samples
  )
}

# Web tools reach the network through Inspect's bridge rather than the
# container, so cutting egress isn't enough on its own. Subagents are barred for
# a different reason: their work doesn't round-trip into the solver transcript,
# so evidence gathered inside one is invisible to the grader's provenance check.
closed_book_disallowed_tools <- function() {
  c("WebSearch", "WebFetch", "Agent", "Task")
}

# Mirrors the provider-agnostic half of commons' system prompt (how to answer,
# brevity, state your assumptions) and drops the parts about measures and the
# run_sql/run_r tools, which this arm doesn't have.
closed_book_system_prompt <- function() {
  paste0(
    "You are a self-service data analyst for your organization. You answer ",
    "questions about its data, accurately and concisely. Today's date is ",
    Sys.Date(),
    ".\n\n",
    "The repository in your working directory is the only source of data ",
    "available to you. Do not use the web, or your own knowledge of these ",
    "projects, for any figure you report.\n\n",
    "- If the available data cannot answer the question, say so plainly and ",
    "say what is missing.\n",
    "- Surface the answer directly and state any assumptions you made to ",
    "reach it. Don't over-interpret or editorialize.\n",
    "- Be brief. Lead with the answer.\n",
    "- Refrain from excessive text formatting. If the answer is shorter than ",
    "a few sentences, it should not contain bolding or italicization."
  )
}

run_chat_async <- function(chat, input) {
  done <- FALSE
  error <- NULL

  promises::then(
    chat$chat_async(input),
    onFulfilled = function(value) done <<- TRUE,
    onRejected = function(e) {
      error <<- e
      done <<- TRUE
    }
  )

  while (!done) {
    later::run_now(0.25)
  }

  if (!is.null(error)) {
    stop(error)
  }

  invisible(chat)
}

strip_citations <- function(text) {
  trimws(gsub("<citation[^>]*>.*?</citation>", "", text))
}

failure_chat <- function(base_chat, input, condition) {
  msg <- if (inherits(condition, "condition")) {
    conditionMessage(condition)
  } else {
    "No response was returned."
  }

  chat <- base_chat$clone()
  chat$set_turns(list(
    ellmer::UserTurn(as.character(input)),
    ellmer::AssistantTurn(paste0("ERROR: ", msg))
  ))
  chat
}
