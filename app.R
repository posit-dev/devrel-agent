library(shiny)

source("agent.R")

welcome_message <- paste(
  "### DevRel Agent",
  "\n\nInvestigate adoption, engagement, and growth across Posit's open source projects.",
  "\n\nUses data from GitHub, CRAN, PyPI, Plausible, OpenVSX, YouTube, and RSS feeds."
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
