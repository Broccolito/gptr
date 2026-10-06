library(shiny)
library(bslib)

ui = page_fixed(
  h2("Sales by region"),
  tableOutput("tbl")
)

server = function(input, output) {
  output$tbl = renderTable({
    agg = aggregate(cbind(units, revenue) ~ region, sales, sum)
    agg$orders = as.vector(table(sales$region)[agg$region])
    agg = agg[order(agg$revenue), ]
    data.frame(Region = agg$region, Orders = agg$orders,
               Units = format(agg$units, big.mark = ","),
               Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","))
  })
}

shinyApp(ui, server)
