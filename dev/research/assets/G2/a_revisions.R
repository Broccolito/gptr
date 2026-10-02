# G2 (a) revisions: one functional change request per level applied to all four apps as exact-match
# edits (Pi edit semantics: each oldText unique in the original file). Writes a_revised/ and prints the
# output-token cost of the edit call vs a full rewrite (write call) for each app.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
src = file.path(G2, "a_apps"); dst = file.path(G2, "a_revised")
unlink(dst, recursive = TRUE)
e = function(old, new) list(oldText = old, newText = new)
R = list()
R$L1 = list(
  shiny_a = list(e('Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","))',
                   'Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","),\n               "Avg price" = sprintf("%.2f", tapply(sales$price, sales$region, mean)[agg$region]),\n               check.names = FALSE)')),
  shiny_b = list(e('Revenue = sum(d$revenue))', 'Revenue = sum(d$revenue),\n               "Avg price" = mean(d$price), check.names = FALSE)'),
                 e('formatCurrency("Units", currency = "", digits = 0)', 'formatCurrency("Units", currency = "", digits = 0) |>\n      formatRound("Avg price", digits = 2)')),
  html_a = list(e('<th>Revenue</th></tr></thead>', '<th>Revenue</th><th>Avg price</th></tr></thead>'),
                e('{orders: 0, units: 0, revenue: 0}', '{orders: 0, units: 0, revenue: 0, price: 0}'),
                e('a.revenue += r.revenue;', 'a.revenue += r.revenue; a.price += r.price;'),
                e('<td>${fmt2(a.revenue)}</td>', '<td>${fmt2(a.revenue)}</td><td>${(a.price / a.orders).toFixed(2)}</td>')),
  html_b = list(e('<th>Revenue</th></tr>', '<th>Revenue</th><th>Avg price</th></tr>'),
                e('orders: 0, units: 0, revenue: 0 };', 'orders: 0, units: 0, revenue: 0, price: 0 };'),
                e('groups[row.region].revenue += row.revenue;', 'groups[row.region].revenue += row.revenue;\n        groups[row.region].price += row.price;'),
                e('g.revenue.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })];',
                  'g.revenue.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }),\n                  (g.price / g.orders).toFixed(2)];')))
R$L2 = list(
  shiny_a = list(e('col = "steelblue"', 'col = "darkorange"')),
  shiny_b = list(e('type = "bar")', 'type = "bar", marker = list(color = "darkorange"))')),
  html_a = list(e('y: MONTHS.map(m => rev[m])}]', 'y: MONTHS.map(m => rev[m]), marker: {color: "darkorange"}}]')),
  html_b = list(e('marker: { color: "#4682b4" }', 'marker: { color: "darkorange" }')))
R$L3 = list(
  shiny_a = list(e('value_box("Average price", textOutput("vb_price"))', 'value_box("Average price", textOutput("vb_price")),\n    value_box("Orders", textOutput("vb_orders"))'),
                 e('output$vb_price = renderText(sprintf("%.2f", mean(sel()$price)))', 'output$vb_price = renderText(sprintf("%.2f", mean(sel()$price)))\n  output$vb_orders = renderText(format(nrow(sel()), big.mark = ","))')),
  shiny_b = list(e('div(class = "col-sm-4",', 'div(class = "col-sm-3",'),
                 e('value_card("Average price", "vb_price")', 'value_card("Average price", "vb_price"),\n        value_card("Orders", "vb_orders")'),
                 e('sprintf("%.2f", mean(filtered()$price))\n  })', 'sprintf("%.2f", mean(filtered()$price))\n  })\n  output$vb_orders = renderText({\n    format(nrow(filtered()), big.mark = ",")\n  })')),
  html_a = list(e('<h3 id="vb_price"></h3></div></div>', '<h3 id="vb_price"></h3></div></div>\n      <div class="col"><div class="card card-body"><div>Orders</div><h3 id="vb_orders"></h3></div></div>'),
                e('.toFixed(2);\n', '.toFixed(2);\n  document.getElementById("vb_orders").textContent = fmt(rows.length, 0);\n')),
  html_b = list(e('<div class="value" id="vb_price"></div></div>', '<div class="value" id="vb_price"></div></div>\n      <div class="box"><div class="label">Orders</div><div class="value" id="vb_orders"></div></div>'),
                e('$("#vb_price").text((sumBy(rows, "price") / rows.length).toFixed(2));', '$("#vb_price").text((sumBy(rows, "price") / rows.length).toFixed(2));\n      $("#vb_orders").text(rows.length.toLocaleString("en-US"));')))
R$L4 = list(
  shiny_a = list(e('[c("name", "wt", "mpg", "hp")]', '[c("name", "wt", "mpg", "hp", "cyl")]')),
  shiny_b = list(e('cars_df[0, c("name", "wt", "mpg", "hp")]', 'cars_df[0, c("name", "wt", "mpg", "hp", "cyl")]'),
                 e('ev$key, c("name", "wt", "mpg", "hp")]', 'ev$key, c("name", "wt", "mpg", "hp", "cyl")]')),
  html_a = list(e('const COLS = ["name", "wt", "mpg", "hp"];', 'const COLS = ["name", "wt", "mpg", "hp", "cyl"];'),
                e('<th>hp</th></tr>', '<th>hp</th><th>cyl</th></tr>')),
  html_b = list(e('var COLUMNS = ["name", "wt", "mpg", "hp"];', 'var COLUMNS = ["name", "wt", "mpg", "hp", "cyl"];')))
R$L5 = list(
  shiny_a = list(e('textOutput(ns("value")))', 'textOutput(ns("value")), textOutput(ns("low")))'),
                 e('output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))',
                   'output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))\n    output$low = renderText(paste("Low stock:", paste(inv()$product[inv()$stock < 50], collapse = ", ")))')),
  shiny_b = list(e('p(textOutput(ns("value"), inline = TRUE))', 'p(textOutput(ns("value"), inline = TRUE)),\n    p(textOutput(ns("low"), inline = TRUE))'),
                 e('paste("Stock value:", format_money(stock_value()))\n    })', 'paste("Stock value:", format_money(stock_value()))\n    })\n\n    output$low = renderText({\n      low = current()$product[current()$stock < 50]\n      paste("Low stock:", paste(low, collapse = ", "))\n    })')),
  html_a = list(e('warehouses.forEach(w => document.getElementById(`${w.id}-value`).textContent = `Stock value: ${money(w.value())}`);',
                  'warehouses.forEach(w => {\n    document.getElementById(`${w.id}-value`).textContent = `Stock value: ${money(w.value())}`;\n    document.getElementById(`${w.id}-low`).textContent = `Low stock: ${w.low().join(", ")}`;\n  });'),
                e('<div class="card-body" id="${id}-value"></div></div>`;', '<div class="card-body"><div id="${id}-value"></div><div id="${id}-low"></div></div></div>`;'),
                e('value: () => rows.reduce((s, r) => s + r.price * r.stock, 0)});', 'value: () => rows.reduce((s, r) => s + r.price * r.stock, 0),\n    low: () => rows.filter(r => r.stock < 50).map(r => r.product)});')),
  html_b = list(e('$root.append($("<p>").attr("id", this.id + "-value"));', '$root.append($("<p>").attr("id", this.id + "-value"));\n        $root.append($("<p>").attr("id", this.id + "-low"));'),
                e('$("#" + this.id + "-value").text("Stock value: " + formatMoney(this.value()));',
                  '$("#" + this.id + "-value").text("Stock value: " + formatMoney(this.value()));\n        var low = this.rows.filter(function (row) { return row.stock < 50; }).map(function (row) { return row.product; });\n        $("#" + this.id + "-low").text("Low stock: " + low.join(", "));')))

count_fixed = function(x, pat) {
  m = gregexpr(pat, x, fixed = TRUE)[[1]]
  if (m[1] == -1) 0L else length(m)
}
rows = list()
for (lv in names(R)) for (impl in names(R[[lv]])) {
  ext = if (startsWith(impl, "shiny")) ".R" else ".html"
  path = file.path(lv, paste0(impl, ext))
  x = paste(readLines(file.path(src, path), warn = FALSE), collapse = "\n")
  y = x
  for (ed in R[[lv]][[impl]]) {
    stopifnot(count_fixed(x, ed$oldText) == 1)          # unique in the ORIGINAL file (Pi semantics)
    y = sub(ed$oldText, ed$newText, y, fixed = TRUE)
  }
  dir.create(file.path(dst, lv), recursive = TRUE, showWarnings = FALSE)
  writeLines(y, file.path(dst, path))
  if (ext == ".R") parse(text = y)
  edit_call = j(list(path = path, edits = R[[lv]][[impl]]))
  write_call = j(list(path = path, content = y))
  rows[[length(rows) + 1]] = data.frame(level = lv, impl, n_edits = length(R[[lv]][[impl]]),
    edit_tok = tok_o200k(edit_call), rewrite_tok = tok_o200k(write_call))
}
d = do.call(rbind, rows)
saveRDS(d, file.path(G2, "a_rev_calls.rds"))
d$rewrite_over_edit = round(d$rewrite_tok / d$edit_tok, 1)
print(d, row.names = FALSE)
d$side = ifelse(startsWith(d$impl, "shiny"), "shiny", "html")
s = aggregate(cbind(edit_tok, rewrite_tok) ~ level + side, d, mean)
s = reshape(s, idvar = "level", timevar = "side", direction = "wide")
s$edit_html_over_shiny = round(s$edit_tok.html / s$edit_tok.shiny, 2)
s$rewrite_html_over_shiny = round(s$rewrite_tok.html / s$rewrite_tok.shiny, 2)
cat("\nMean per side (o200k output tokens of the tool-call arguments):\n")
print(s, row.names = FALSE)
cat(sprintf("\nAll levels: edit total shiny %d vs html %d (x%.2f); rewrite total shiny %d vs html %d (x%.2f)\n",
            sum(d$edit_tok[d$side == "shiny"]), sum(d$edit_tok[d$side == "html"]),
            sum(d$edit_tok[d$side == "html"]) / sum(d$edit_tok[d$side == "shiny"]),
            sum(d$rewrite_tok[d$side == "shiny"]), sum(d$rewrite_tok[d$side == "html"]),
            sum(d$rewrite_tok[d$side == "html"]) / sum(d$rewrite_tok[d$side == "shiny"])))
cat(sprintf("Rewrite / edit: shiny %.1fx, html %.1fx (sum over levels)\n",
            sum(d$rewrite_tok[d$side == "shiny"]) / sum(d$edit_tok[d$side == "shiny"]),
            sum(d$rewrite_tok[d$side == "html"]) / sum(d$edit_tok[d$side == "html"])))
