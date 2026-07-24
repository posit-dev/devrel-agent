library(shiny)

source("agent.R")

ui <- bslib::page_fillable(
  commons::commons_ui("chat")
)

server <- function(input, output, session) {
  commons::commons_server("chat", devrel_agent)
}

shinyApp(ui, server)
