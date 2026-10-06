library(shiny)
library(plotly)

ui = fluidPage(
  titlePanel("Revenue by month"),
  sidebarLayout(
    sidebarPanel(
      selectInput("region", "Region",
                  choices = c("All", "East", "North", "South", "West"), selected = "All")
    ),
    mainPanel(
      textOutput("n"),
      plotlyOutput("chart")
    )
  )
)

server = function(input, output, session) {
  filtered = reactive({
    if (input$region == "All") {
      sales
    } else {
      subset(sales, region == input$region)
    }
  })

  output$n = renderText({
    paste(nrow(filtered()), "orders")
  })

  output$chart = renderPlotly({
    monthly = aggregate(revenue ~ month, data = filtered(), FUN = sum)
    plot_ly(monthly, x = ~month, y = ~revenue, type = "bar", marker = list(color = "darkorange")) |>
      layout(xaxis = list(title = "Month"), yaxis = list(title = "Revenue"))
  })
}

shinyApp(ui, server)
