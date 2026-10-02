library(shiny)

format_money = function(x) {
  formatC(x, format = "f", digits = 2, big.mark = ",")
}

warehouseUI = function(id, title) {
  ns = NS(id)
  tagList(
    h3(title),
    uiOutput(ns("table")),
    p(textOutput(ns("value"), inline = TRUE)),
    p(textOutput(ns("low"), inline = TRUE))
  )
}

warehouseServer = function(id, inventory) {
  moduleServer(id, function(input, output, session) {
    ns = session$ns

    output$table = renderUI({
      rows = lapply(seq_len(nrow(inventory)), function(i) {
        tags$tr(
          tags$td(inventory$product[i]),
          tags$td(numericInput(ns(paste0("price_", i)), NULL, inventory$price[i], min = 0, width = "100px")),
          tags$td(numericInput(ns(paste0("stock_", i)), NULL, inventory$stock[i], min = 0, width = "100px"))
        )
      })
      tags$table(
        class = "table",
        tags$thead(tags$tr(tags$th("product"), tags$th("price"), tags$th("stock"))),
        tags$tbody(rows)
      )
    })

    current = reactive({
      n = nrow(inventory)
      data.frame(
        product = inventory$product,
        price = vapply(seq_len(n), function(i) input[[paste0("price_", i)]] %||% inventory$price[i], numeric(1)),
        stock = vapply(seq_len(n), function(i) input[[paste0("stock_", i)]] %||% inventory$stock[i], numeric(1))
      )
    })

    stock_value = reactive({
      sum(current()$price * current()$stock, na.rm = TRUE)
    })

    output$value = renderText({
      paste("Stock value:", format_money(stock_value()))
    })

    output$low = renderText({
      low = current()$product[current()$stock < 50]
      paste("Low stock:", paste(low, collapse = ", "))
    })

    stock_value
  })
}

ui = fluidPage(
  titlePanel("Inventory"),
  fluidRow(
    column(6, warehouseUI("a", "Warehouse A")),
    column(6, warehouseUI("b", "Warehouse B"))
  ),
  h4(textOutput("total"))
)

server = function(input, output, session) {
  value_a = warehouseServer("a", inv_a)
  value_b = warehouseServer("b", inv_b)

  output$total = renderText({
    paste("Total stock value:", format_money(value_a() + value_b()))
  })
}

shinyApp(ui, server)
