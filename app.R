library(shiny)

# source("deploy.R")
source("agent.R")

welcome_message <- paste(
  "### DevRel Agent",
  "\n\nInvestigate adoption, engagement, and growth across Posit's open source projects.\n\n",
  "- <span class='suggestion'>How many CRAN downloads were there last month?</span>\n",
  "- <span class='suggestion'>How many website pageviews were there last month?</span>\n",
  "- <span class='suggestion'>Why would I use air?</span>\n"
)

ui <- bslib::page_fillable(
  title = "DevRel Agent",
  commons::commons_ui(
    "chat",
    greeting = welcome_message
  )
)

server <- function(input, output, session) {
  commons::commons_server("chat", devrel_agent)
}

shinyApp(ui, server)
