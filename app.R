library(shiny)
library(bslib)

# source("deploy.R")
source("agent.R")

addResourcePath("assets", "_assets")

# What the data covers, for the welcome message: it's the same for every
# session of a deployment.
data_facts <- DBI::dbGetQuery(
  devrel_con,
  "SELECT (SELECT COUNT(*) FROM projects) AS projects, as_of FROM meta"
)

welcome_message <- paste0(
  "Investigate adoption, engagement, and growth across ",
  format(data_facts$projects, big.mark = ","),
  " of Posit's open source projects, with data through ",
  trimws(format(data_facts$as_of, "%B %e, %Y")),
  ".\n\n",
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
      tags$span("DevRel Agent", style = "font-weight: 200; font-size: 1.4rem;")
    )
  ),
  id = "chat",
  window_title = "DevRel Agent",
  theme = commons::commons_theme(brand = TRUE),
  greeting = welcome_message
)

server <- function(input, output, session) {
  # One agent per session: a shared agent would interleave concurrent
  # users' turns into a single conversation.
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
