# Render readable solver + grader transcripts from a vitals JSON log.
#
#   Rscript evals/transcript.R <log.json> [out_dir]     # all samples
#   Rscript evals/transcript.R <log.json> - <sample_id> # one sample to stdout
#
# Solver tool calls/results serialize fully in the log; the grader transcript
# drops tool calls, so the rubric item scores are recovered from the str()
# lines vitals keeps in scorer_metadata.

render_log <- function(path, out_dir = NULL, sample_id = NULL) {
  log <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  samples <- log$samples

  ids <- vapply(samples, function(s) as.character(s$id), character(1))
  if (!is.null(sample_id)) {
    samples <- samples[ids == sample_id]
    if (!length(samples)) {
      stop("No sample with id ", sample_id, " in ", path)
    }
  }

  rendered <- lapply(samples, render_sample)

  if (is.null(out_dir)) {
    cat(paste(vapply(rendered, paste, character(1), collapse = "\n"), collapse = "\n\n---\n\n"), "\n")
    return(invisible(NULL))
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(samples)) {
    file <- file.path(out_dir, paste0(samples[[i]]$id, ".md"))
    writeLines(rendered[[i]], file)
  }
  invisible(file.path(out_dir, paste0(vapply(samples, function(s) as.character(s$id), character(1)), ".md")))
}

render_sample <- function(s) {
  score <- s$scores[[1]]

  c(
    paste0("# Sample ", s$id),
    "",
    paste0("**Score:** ", deparse(score$value)),
    "",
    "## Question",
    "",
    fenced(s$input),
    "",
    "## Grading notes (target)",
    "",
    fenced(s$target),
    "",
    "## Solver trajectory",
    "",
    render_messages(s$messages),
    "",
    "## Grader trajectory",
    "",
    paste0("**Explanation field:** ", one_line(score$explanation)),
    "",
    render_messages(score$metadata$grading),
    "",
    "### scorer_metadata (str dump; includes rubric item scores when present)",
    "",
    fenced(paste(unlist(score$metadata$scorer_metadata), collapse = "\n"))
  )
}

render_messages <- function(messages) {
  out <- character()
  for (m in messages) {
    header <- paste0("### ", toupper(m$role %||% "?"))
    if (!is.null(m$`function`)) {
      header <- paste0(header, " (result of `", m$`function`, "`)")
    }
    out <- c(out, header, "")

    out <- c(out, render_content(m$content), "")

    for (call in m$tool_calls %||% list()) {
      args <- jsonlite::toJSON(call$arguments, auto_unbox = TRUE, pretty = TRUE)
      out <- c(
        out,
        paste0("**Tool call:** `", call$`function`, "`"),
        "",
        fenced(args, lang = "json"),
        ""
      )
    }
  }
  out
}

render_content <- function(content) {
  if (is.null(content)) {
    return(character())
  }
  if (is.character(content)) {
    return(fenced(content))
  }

  out <- character()
  for (block in content) {
    if (identical(block$type, "text") && nzchar(block$text %||% "")) {
      out <- c(out, block$text, "")
    } else if (identical(block$type, "reasoning")) {
      reasoning <- block$reasoning %||% ""
      label <- if (nzchar(reasoning)) reasoning else "[encrypted/redacted]"
      out <- c(out, paste0("*reasoning:* ", one_line(label, width = 2000)), "")
    }
  }
  out
}

fenced <- function(text, lang = "") {
  text <- paste(as.character(text), collapse = "\n")
  c(paste0("```", lang), text, "```")
}

one_line <- function(text, width = 400) {
  text <- gsub("\\s+", " ", paste(as.character(text), collapse = " "))
  if (nchar(text) > width) paste0(substr(text, 1, width), "...") else text
}

`%||%` <- function(x, y) if (is.null(x)) y else x

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (!length(args)) {
    stop("Usage: Rscript evals/transcript.R <log.json> [out_dir | - <sample_id>]")
  }
  if (length(args) >= 2 && args[[2]] == "-") {
    render_log(args[[1]], sample_id = args[[3]])
  } else {
    files <- render_log(args[[1]], out_dir = if (length(args) >= 2) args[[2]] else "evals/logs/transcripts")
    cat("Wrote", length(files), "transcripts to", dirname(files[[1]]), "\n")
  }
}
