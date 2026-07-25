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
      agent <- build_devrel_agent(con, client_factory = client_factory)
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
