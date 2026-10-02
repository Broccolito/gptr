library(shiny)
library(DT)

region_summary = function(df) {
  out = do.call(rbind, lapply(split(df, df$region), function(d) {
    data.frame(Region = d$region[1], Orders = nrow(d), Units = sum(d$units), Revenue = sum(d$revenue))
  }))
  out[order(out$Revenue, decreasing = TRUE), ]
}

ui = fluidPage(
  titlePanel("Sales by region"),
  DTOutput("summary_table")
)

server = function(input, output, session) {
  output$summary_table = renderDT({
    datatable(region_summary(sales), rownames = FALSE,
              options = list(dom = "t", paging = FALSE, ordering = FALSE)) |>
      formatCurrency("Revenue", currency = "", digits = 2) |>
      formatCurrency("Units", currency = "", digits = 0)
  })
}

shinyApp(ui, server)
