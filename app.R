library(shiny)
library(bslib)

# source("deploy.R")
source("agent.R")

addResourcePath("assets", "_assets")

welcome_message <- paste(
  "Investigate adoption, engagement, and growth across Posit's open source projects.\n\n",
  "Here are some example questions:\n\n",
  "- <span class='suggestion'>How many CRAN downloads were there last month?</span>\n",
  "- <span class='suggestion'>How many website pageviews were there last month?</span>\n",
  "- <span class='suggestion'>Why would I use air?</span>\n"
)

ui <- shinychat::page_chat(
  title = list(
    tags$span(
      style = "display: inline-flex; align-items: center; gap: 0.65rem;",
      tags$img(
        src = "assets/posit-logo-mark.svg",
        height = "26px",
        alt = "Posit",
        style = "display: block;"
      ),
      tags$span("devrel agent", style = "font-weight: 200; font-size: 1.4rem;")
    )
  ),
  id = "chat",
  window_title = "devrel agent",
  theme = commons::commons_theme(brand = TRUE),
  greeting = welcome_message
)

server <- function(input, output, session) {
  # One agent per session: shinychat::chat_server() streams on the client
  # directly, so a shared agent would interleave concurrent users' turns
  # into a single conversation. Construction is ~90ms (local DuckDB table
  # checks + dictionary parse), well within the session-startup budget.
  agent <- build_devrel_agent(
    con = devrel_con,
    client = ellmer::chat_openai(
      model = "gpt-5.6-terra",
      params = ellmer::params(reasoning_effort = "medium")
    )
  )
  commons::commons_server("chat", agent)
}

shinyApp(ui, server)
