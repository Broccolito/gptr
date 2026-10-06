library(shiny)
library(bslib)

ui = page_fillable(
  h2("Car explorer"),
  layout_columns(
    plotOutput("plot", brush = "brush"),
    card(textOutput("n"), tableOutput("selected"), downloadButton("download", "Download CSV"))
  )
)

server = function(input, output) {
  picked = reactive(brushedPoints(cars_df, input$brush, xvar = "wt", yvar = "mpg")[c("name", "wt", "mpg", "hp", "cyl")])
  output$plot = renderPlot(plot(mpg ~ wt, cars_df, pch = 19))
  output$n = renderText(paste(nrow(picked()), "selected"))
  output$selected = renderTable(picked())
  output$download = downloadHandler("selected.csv", function(file) write.csv(picked(), file, row.names = FALSE))
}

shinyApp(ui, server)
