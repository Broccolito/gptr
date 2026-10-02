library(shiny)
library(bslib)

ui = page_sidebar(
  title = "Revenue by month",
  sidebar = sidebar(selectInput("region", "Region", c("All", sort(unique(sales$region))))),
  textOutput("n"),
  plotOutput("chart")
)

server = function(input, output) {
  sel = reactive(if (input$region == "All") sales else sales[sales$region == input$region, ])
  output$n = renderText(paste(nrow(sel()), "orders"))
  output$chart = renderPlot({
    rev = tapply(sel()$revenue, sel()$month, sum)
    barplot(rev, col = "darkorange", ylab = "Revenue")
  })
}

shinyApp(ui, server)
