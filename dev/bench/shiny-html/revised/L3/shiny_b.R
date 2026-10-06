library(shiny)
library(plotly)
library(DT)

value_card = function(title, output_id) {
  div(class = "col-sm-3",
      wellPanel(
        h5(title),
        h3(textOutput(output_id))
      ))
}

ui = fluidPage(
  titlePanel("Sales dashboard"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("region", "Region", choices = c("All", "East", "North", "South", "West"))
    ),
    mainPanel(
      width = 9,
      fluidRow(
        value_card("Total revenue", "vb_revenue"),
        value_card("Total units", "vb_units"),
        value_card("Average price", "vb_price"),
        value_card("Orders", "vb_orders")
      ),
      tabsetPanel(
        id = "tabs",
        tabPanel("Trend", plotlyOutput("trend")),
        tabPanel("Regions", plotlyOutput("regions")),
        tabPanel("Data", DTOutput("data"))
      )
    )
  )
)

server = function(input, output, session) {
  filtered = reactive({
    if (input$region == "All") sales else subset(sales, region == input$region)
  })

  output$vb_revenue = renderText({
    formatC(sum(filtered()$revenue), format = "f", digits = 2, big.mark = ",")
  })
  output$vb_units = renderText({
    format(sum(filtered()$units), big.mark = ",")
  })
  output$vb_price = renderText({
    sprintf("%.2f", mean(filtered()$price))
  })
  output$vb_orders = renderText({
    format(nrow(filtered()), big.mark = ",")
  })

  output$trend = renderPlotly({
    monthly = aggregate(revenue ~ month, data = filtered(), FUN = sum)
    plot_ly(monthly, x = ~month, y = ~revenue, type = "scatter", mode = "lines+markers") |>
      layout(xaxis = list(title = "Month"), yaxis = list(title = "Revenue"))
  })

  output$regions = renderPlotly({
    by_region = aggregate(revenue ~ region, data = sales, FUN = sum)
    plot_ly(by_region, x = ~region, y = ~revenue, type = "bar") |>
      layout(xaxis = list(title = "Region"), yaxis = list(title = "Revenue"))
  })

  output$data = renderDT({
    datatable(head(filtered(), 10), rownames = FALSE, options = list(dom = "t"))
  })
}

shinyApp(ui, server)
