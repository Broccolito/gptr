library(shiny)
library(bslib)
library(ggplot2)

ui = page_sidebar(
  title = "Sales dashboard",
  sidebar = sidebar(selectInput("region", "Region", c("All", sort(unique(sales$region))))),
  layout_columns(
    value_box("Total revenue", textOutput("vb_revenue")),
    value_box("Total units", textOutput("vb_units")),
    value_box("Average price", textOutput("vb_price"))
  ),
  navset_card_tab(
    nav_panel("Trend", plotOutput("trend")),
    nav_panel("Regions", plotOutput("regions")),
    nav_panel("Data", tableOutput("data"))
  )
)

server = function(input, output) {
  sel = reactive(if (input$region == "All") sales else sales[sales$region == input$region, ])
  money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")
  output$vb_revenue = renderText(money(sum(sel()$revenue)))
  output$vb_units = renderText(format(sum(sel()$units), big.mark = ","))
  output$vb_price = renderText(sprintf("%.2f", median(sel()$price)))
  output$trend = renderPlot({
    m = aggregate(revenue ~ month, sel(), sum)
    ggplot(m, aes(month, revenue, group = 1)) + geom_line() + geom_point()
  })
  output$regions = renderPlot(ggplot(sales, aes(region, revenue)) + geom_col(fill = "steelblue"))
  output$data = renderTable(head(sel(), 10))
}

shinyApp(ui, server)
