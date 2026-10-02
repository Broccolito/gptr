# G2 part (a): one functional spec per complexity level

Data (identical for both sides): `sales` (5000 rows: region, month [Jan..Dec], units, price, revenue),
`cars_df` (mtcars + column `name`), `inv_a`, `inv_b` (8 rows each: product, price, stock).
Shiny apps reference the objects by name (they exist in the app's environment, as in the report-17
artifact design). HTML apps load `data/<name>.json` (row-wise JSON exported by the harness) and use
CDN URLs for libraries (localised to package-shipped copies for the offline test).
Money = comma thousands, 2 decimals (12,345.67). Element ids are fixed so one checker tests all apps.

L1 static table: title "Sales by region"; table with columns Region, Orders, Units, Revenue, one
row per region, sorted by revenue descending (Units comma-formatted, Revenue money).

L2 filter + plot: title "Revenue by month"; select #region (All, East, North, South, West; default
All); text #n = "<count> orders"; bar chart #chart of total revenue per month (Jan..Dec) for the
selection.

L3 dashboard: title "Sales dashboard"; sidebar select #region (All + 4 regions); value boxes
"Total revenue" #vb_revenue (money), "Total units" #vb_units (comma int), "Average price" #vb_price
(mean price, 2 decimals); tabs "Trend" (#trend line chart of revenue by month of the selection),
"Regions" (#regions bar chart of revenue by region, all data), "Data" (#data table: first 10 rows
of the selection).

L4 linked brushing + download: title "Car explorer"; scatter #plot of wt (x) vs mpg (y); a
rectangular brush/box-select selects cars; #n = "<k> selected"; table #selected with columns
name, wt, mpg, hp listing all selected cars; button/link #download saves the selected rows as CSV
"selected.csv" (header name,wt,mpg,hp).

L5 editable table with modules: title "Inventory"; the same module/component instantiated twice
(ids a, b; titles "Warehouse A", "Warehouse B"); each shows an editable table #<id>-table
(product, price, stock; price and stock editable) and text #<id>-value = "Stock value: <money>"
(sum of price * stock); global text #total = "Total stock value: <money>" updates on every edit.
