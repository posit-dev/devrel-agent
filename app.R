library(shiny)

source("agent.R")

welcome_message <- paste(
  "### DevRel Agent",
  "\n\nInvestigate adoption, engagement, and growth across Posit's open source projects.\n\n",
  "- <span class='suggestion'>How many CRAN downloads did dplyr get last month?</span>\n",
  "- <span class='suggestion'>Which projects had the most website pageviews last month?</span>\n",
  "- <span class='suggestion'>What makes Air fast?</span>\n"
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
