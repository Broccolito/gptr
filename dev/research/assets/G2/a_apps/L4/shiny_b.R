library(shiny)
library(plotly)
library(DT)

ui = fluidPage(
  titlePanel("Car explorer"),
  fluidRow(
    column(7, plotlyOutput("plot")),
    column(5,
           textOutput("n"),
           DTOutput("selected"),
           downloadButton("download", "Download CSV"))
  )
)

server = function(input, output, session) {
  output$plot = renderPlotly({
    plot_ly(cars_df, x = ~wt, y = ~mpg, key = ~name, type = "scatter", mode = "markers",
            source = "cars") |>
      layout(dragmode = "select") |>
      event_register("plotly_selected")
  })

  selected_rows = reactive({
    ev = event_data("plotly_selected", source = "cars")
    if (is.null(ev) || length(ev$key) == 0) {
      cars_df[0, c("name", "wt", "mpg", "hp")]
    } else {
      cars_df[cars_df$name %in% ev$key, c("name", "wt", "mpg", "hp")]
    }
  })

  output$n = renderText({
    paste(nrow(selected_rows()), "selected")
  })

  output$selected = renderDT({
    datatable(selected_rows(), rownames = FALSE, options = list(dom = "t", paging = FALSE))
  })

  output$download = downloadHandler(
    filename = function() "selected.csv",
    content = function(file) {
      write.csv(selected_rows(), file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
