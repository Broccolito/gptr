library(shiny)
library(bslib)
library(DT)

money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")

warehouse_ui = function(id, title) {
  ns = NS(id)
  card(card_header(title), DTOutput(ns("table")), textOutput(ns("value")))
}

warehouse_server = function(id, data) {
  moduleServer(id, function(input, output, session) {
    inv = reactiveVal(data)
    output$table = renderDT(datatable(data, rownames = FALSE, selection = "none",
                                      editable = list(target = "cell", disable = list(columns = 0))))
    observeEvent(input$table_cell_edit, {
      e = input$table_cell_edit
      d = inv()
      d[e$row, e$col + 1] = as.numeric(e$value)
      inv(d)
    })
    output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))
    reactive(sum(inv()$price * inv()$stock))
  })
}

ui = page_fixed(
  h2("Inventory"),
  layout_columns(warehouse_ui("a", "Warehouse A"), warehouse_ui("b", "Warehouse B")),
  textOutput("total")
)

server = function(input, output) {
  a = warehouse_server("a", inv_a)
  b = warehouse_server("b", inv_b)
  output$total = renderText(paste("Total stock value:", money(a() + b())))
}

shinyApp(ui, server)
