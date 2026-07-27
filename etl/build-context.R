# Crawl opensource.posit.co into one markdown file per page for the agent's
# context layer (see agent.R). Only the /software/<slug>, /about, and
# /blog/<slug> pages are kept: they carry the prose describing what each
# project is and what's been announced, which the metrics tables lack. The
# listing/browse sections (resources, people, tags, events, topics,
# languages) would mostly add BM25 noise for a metrics agent.
#
# Each file opens with frontmatter recording the source URL and retrieval
# date; commons strips frontmatter before indexing, so it's provenance for
# maintainers only.
#
# Usage:
#   Rscript etl/build-context.R [output_dir]

base_url <- "https://opensource.posit.co/"

build_devrel_context <- function(output_dir = "context/opensource-posit-co") {
  links <- ragnar::ragnar_find_links(
    base_url,
    depth = 1L,
    children_only = TRUE,
    url_filter = filter_context_urls
  )
  pages <- keep_context_pages(links)
  check_crawl(pages)

  unlink(output_dir, recursive = TRUE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  failures <- character(0)
  cli::cli_progress_bar("Converting pages", total = length(pages))
  for (url in pages) {
    md <- tryCatch(
      as.character(ragnar::read_as_markdown(url)),
      error = function(e) NA_character_
    )
    if (is.na(md)) {
      failures <- c(failures, url)
    } else {
      writeLines(
        c(
          "---",
          paste0("source_url: ", url),
          paste0("retrieved: ", Sys.Date()),
          "---",
          "",
          md
        ),
        file.path(output_dir, page_filename(url))
      )
    }
    cli::cli_progress_update()
  }
  cli::cli_progress_done()

  report_context_build(output_dir, failures)
  invisible(output_dir)
}

# Applied both to the crawl queue (so unwanted sections are never fetched)
# and to the collected links. Query-string variants of the software index
# (?languages=R and friends) duplicate pages reachable without them.
filter_context_urls <- function(urls) {
  urls <- urls[!grepl("[?#]", urls)]
  top <- sub("/.*", "", sub(base_url, "", urls, fixed = TRUE))
  urls[top %in% c("software", "about", "blog")]
}

# Leaf pages only: /software/ and /blog/ themselves are listings, while
# /about/ is a real overview page.
keep_context_pages <- function(links) {
  links <- sub("/$", "", filter_context_urls(links))
  paths <- sub(base_url, "", links, fixed = TRUE)
  unique(links[grepl("^software/.|^about|^blog/.", paths)])
}

page_filename <- function(url) {
  paste0(gsub("/", "-", sub(base_url, "", url, fixed = TRUE)), ".md")
}

check_crawl <- function(pages, call = rlang::caller_env()) {
  n_software <- sum(grepl(paste0(base_url, "software/"), pages, fixed = TRUE))
  if (n_software < 100) {
    cli::cli_abort(
      "Crawl found only {n_software} software page{?s}; the site structure
       may have changed.",
      call = call
    )
  }
}

report_context_build <- function(output_dir, failures) {
  files <- list.files(output_dir, full.names = TRUE)
  cli::cli_inform(c(
    "v" = "Wrote {length(files)} page{?s} to {.path {output_dir}}
           ({prettyunits::pretty_bytes(sum(file.size(files)))})."
  ))
  if (length(failures) > 0) {
    cli::cli_warn(c(
      "Failed to convert {length(failures)} page{?s}:",
      stats::setNames(failures, rep("*", length(failures)))
    ))
  }
}

if (!interactive() && identical(environment(), globalenv())) {
  args <- commandArgs(trailingOnly = TRUE)
  do.call(build_devrel_context, as.list(args))
}
