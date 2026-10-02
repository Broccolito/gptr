# G2 (a): functional verification of the 20 apps (5 levels x {shiny_a, shiny_b, html_a, html_b}).
# Ladder per app: parse -> launch (Shiny in a callr child; HTML via a static server child) ->
# HTTP 200 -> headless Chrome (chromote) with spec assertions and one interaction per level.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
A = file.path(G2, "a_apps")
source(file.path(A, "data.R"))
APPS = Sys.getenv("G2_APPS", A)
IMPLS = strsplit(Sys.getenv("G2_IMPLS", "shiny_a,shiny_b,html_a,html_b"), ",")[[1]]
money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")
shots = file.path(G2, "a_shots"); dir.create(shots, showWarnings = FALSE)
args = commandArgs(TRUE)
only = if (length(args)) args else NULL

# ---------- expected values (computed in R, independent of the apps) ----------
agg = aggregate(cbind(units, revenue) ~ region, sales, sum)
agg$orders = as.vector(table(sales$region)[agg$region])
agg = agg[order(-agg$revenue), ]
exp_l1 = paste(sprintf("%s|%d|%s|%s", agg$region, agg$orders, format(agg$units, big.mark = ",", trim = TRUE),
                       money(agg$revenue)), collapse = "||")
n_north = sum(sales$region == "North")
rev_north = sum(sales$revenue[sales$region == "North"])
west = sales[sales$region == "West", ]
exp_l3_all = c(money(sum(sales$revenue)), format(sum(sales$units), big.mark = ","), sprintf("%.2f", mean(sales$price)))
exp_l3_west = money(sum(west$revenue))
val = function(d) sum(d$price * d$stock)
inv_a2 = inv_a; inv_a2$stock[1] = 100
exp_l5_init = c(money(val(inv_a)), money(val(inv_b)), money(val(inv_a) + val(inv_b)))
exp_l5_edit = c(money(val(inv_a2)), money(val(inv_a2) + val(inv_b)))
cars_js = j(cars_df[c("name", "wt", "mpg")])

# ---------- static site for the HTML apps (CDN URLs -> package-shipped copies; no network) ----------
L = .libPaths()
pkgfile = function(pkg, ...) system.file(..., package = pkg)
site = file.path(G2, "a_site"); unlink(site, recursive = TRUE)
dir.create(file.path(site, "vendor"), recursive = TRUE); dir.create(file.path(site, "data"))
vendor = c(
  "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" = pkgfile("bslib", "css-precompiled/5/bootstrap.min.css"),
  "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" = pkgfile("bslib", "lib/bs5/dist/js/bootstrap.bundle.min.js"),
  "https://cdn.plot.ly/plotly-2.35.2.min.js" = pkgfile("plotly", "htmlwidgets/lib/plotlyjs/plotly-latest.min.js"),
  "https://cdn.datatables.net/2.1.8/css/dataTables.dataTables.min.css" = pkgfile("DT", "htmlwidgets/lib/datatables/css/jquery.dataTables.extra.css"),
  "https://cdn.datatables.net/2.1.8/js/dataTables.min.js" = pkgfile("DT", "htmlwidgets/lib/datatables/js/jquery.dataTables.min.js"),
  "https://code.jquery.com/jquery-3.7.1.min.js" = pkgfile("shiny", "www/shared/jquery.min.js"))
local_name = paste0("vendor/v", seq_along(vendor), sub(".*([.](js|css))$", "\\1", names(vendor)))
invisible(file.copy(vendor, file.path(site, local_name)))
for (nm in c("sales", "cars_df", "inv_a", "inv_b")) {
  jsonlite::write_json(get(nm), file.path(site, "data", paste0(nm, ".json")), dataframe = "rows", digits = NA)
}
localise = function(x) {
  for (i in seq_along(vendor)) x = gsub(names(vendor)[i], local_name[i], x, fixed = TRUE)
  x
}
static_port = 18231L
static = callr::r_bg(function(dir, port, lib) {
  .libPaths(lib)
  httpuv::runStaticServer(dir, port = port, browse = FALSE)
}, list(dir = site, port = static_port, lib = L), supervise = TRUE)

# ---------- helpers ----------
http_ok = function(url, timeout = 30) {
  t0 = Sys.time()
  while (as.numeric(Sys.time() - t0, units = "secs") < timeout) {
    st = tryCatch(curl::curl_fetch_memory(url)$status_code, error = function(e) NA)
    if (identical(st, 200L)) return(TRUE)
    Sys.sleep(0.2)
  }
  FALSE
}
launch_shiny = function(file, port) {
  dir = tempfile("app"); dir.create(dir)
  file.copy(file, file.path(dir, "app.R"))
  log = tempfile(fileext = ".log")
  p = callr::r_bg(function(dir, port, data, lib) {
    .libPaths(lib)
    source(data)
    shiny::runApp(dir, port = port, launch.browser = FALSE)
  }, list(dir = dir, port = port, data = file.path(A, "data.R"), lib = L),
  stdout = log, stderr = "2>&1", supervise = TRUE)
  list(proc = p, log = log)
}
static_check = function(file) {
  ex = tryCatch(parse(file, keep.source = FALSE), error = function(e) e)
  if (inherits(ex, "error")) return(paste("parse error:", conditionMessage(ex)))
  last = ex[[length(ex)]]
  if (!is.call(last) || !identical(deparse(last[[1]]), "shinyApp")) return("last expression is not shinyApp()")
  "ok"
}

seed = if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv()) else NULL
chrome = chromote::Chromote$new()
if (!is.null(seed)) assign(".Random.seed", seed, globalenv())

session_run = function(url, steps, png) {
  b = chrome$new_session(width = 1200, height = 900)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  errs = character()
  b$Runtime$enable()
  b$Runtime$exceptionThrown(callback_ = function(m) errs <<- c(errs, m$exceptionDetails$exception$description %||% m$exceptionDetails$text))
  ld = b$Page$loadEventFired(wait_ = FALSE)
  b$Page$navigate(url, wait_ = FALSE)
  b$wait_for(ld)
  ev = function(js) {
    r = b$Runtime$evaluate(js, returnByValue = TRUE, awaitPromise = TRUE)
    if (!is.null(r$exceptionDetails)) return(paste("JSERR:", r$exceptionDetails$exception$description %||% r$exceptionDetails$text))
    r$result$value
  }
  wait = function(pred, timeout = 15) {
    t0 = Sys.time()
    repeat {
      v = ev(sprintf("(()=>{try{return !!(%s)}catch(e){return false}})()", pred))
      if (isTRUE(v)) return(TRUE)
      if (as.numeric(Sys.time() - t0, units = "secs") > timeout) return(FALSE)
      Sys.sleep(0.15)
    }
  }
  res = list()
  for (s in steps) {
    if (!is.null(s$drag)) drag(b, ev, s$drag)
    if (!is.null(s$act)) ev(s$act)
    ok = wait(s$pred, s$timeout %||% 15)
    detail = if (!ok && !is.null(s$show)) ev(s$show) else ""
    res[[length(res) + 1]] = data.frame(step = s$name, ok = ok, detail = substr(paste(detail, collapse = " "), 1, 200))
  }
  out_err = ev("Array.from(document.querySelectorAll('.shiny-output-error:not(.shiny-output-error-validation)')).length")
  shot = b$Page$captureScreenshot(format = "png")$data
  writeBin(jsonlite::base64_dec(shot), png)
  list(steps = do.call(rbind, res), js_errors = unique(errs), output_errors = out_err %||% 0)
}
drag = function(b, ev, sel) {
  r = ev(sprintf("(()=>{const e=document.querySelector('%s'); const r=e.getBoundingClientRect(); return [r.left,r.top,r.width,r.height]})()", sel))
  r = unlist(r)
  x0 = r[1] + 0.30 * r[3]; y0 = r[2] + 0.25 * r[4]; x1 = r[1] + 0.62 * r[3]; y1 = r[2] + 0.75 * r[4]
  b$Input$dispatchMouseEvent(type = "mouseMoved", x = x0, y = y0)
  b$Input$dispatchMouseEvent(type = "mousePressed", x = x0, y = y0, button = "left", buttons = 1, clickCount = 1)
  for (k in 1:8) {
    b$Input$dispatchMouseEvent(type = "mouseMoved", x = x0 + (x1 - x0) * k / 8, y = y0 + (y1 - y0) * k / 8,
                               button = "left", buttons = 1)
    Sys.sleep(0.03)
  }
  b$Input$dispatchMouseEvent(type = "mouseReleased", x = x1, y = y1, button = "left", buttons = 1, clickCount = 1)
  Sys.sleep(0.5)
}

# ---------- per-level steps (same assertions for all four implementations) ----------
txt = function(sel) sprintf("(document.querySelector('%s')||{textContent:''}).textContent.trim()", sel)
set_select = function(v) sprintf("(()=>{const s=document.getElementById('region'); if (s.selectize) s.selectize.setValue('%s'); else {s.value='%s'; s.dispatchEvent(new Event('change',{bubbles:true}));} return 1})()", v, v)
chart_js = function(id) sprintf("(document.querySelectorAll('#%s .main-svg').length>0 || !!document.querySelector('#%s img[src^=\"data:image\"]'))", id, id)
rows_js = "[...document.querySelectorAll('table tbody tr')].filter(tr=>tr.cells.length>=4).map(tr=>[...tr.cells].slice(0,4).map(c=>c.textContent.trim()).join('|')).join('||')"

steps_for = function(level, impl) {
  is_shiny = startsWith(impl, "shiny")
  switch(level,
    L1 = list(list(name = "table rows sorted, formatted", pred = sprintf("%s === '%s'", rows_js, exp_l1), show = rows_js)),
    L2 = list(
      list(name = "initial count 5000", pred = sprintf("%s === '5000 orders' && %s", txt("#n"), chart_js("chart")), show = txt("#n")),
      list(name = "select North -> count + bars", act = set_select("North"),
           pred = sprintf("%s === '%d orders' && %s && (!document.getElementById('chart').data || Math.abs(document.getElementById('chart').data[0].y.reduce((a,b)=>a+b,0) - %.4f) < 0.01)",
                          txt("#n"), n_north, chart_js("chart"), rev_north), show = txt("#n"))),
    L3 = list(
      list(name = "value boxes (All) + trend chart + 3 tabs",
           pred = sprintf("%s==='%s' && %s==='%s' && %s==='%s' && %s && ['Trend','Regions','Data'].every(t=>[...document.querySelectorAll('a,button')].some(e=>e.textContent.trim()===t))",
                          txt("#vb_revenue"), exp_l3_all[1], txt("#vb_units"), exp_l3_all[2], txt("#vb_price"), exp_l3_all[3], chart_js("trend")),
           show = sprintf("[%s,%s,%s].join(' ; ')", txt("#vb_revenue"), txt("#vb_units"), txt("#vb_price"))),
      list(name = "select West -> revenue box", act = set_select("West"), pred = sprintf("%s==='%s'", txt("#vb_revenue"), exp_l3_west), show = txt("#vb_revenue")),
      list(name = "Data tab -> 10 West rows",
           act = "[...document.querySelectorAll('a,button')].find(e=>e.textContent.trim()==='Data').click()",
           pred = "(()=>{const r=[...document.querySelectorAll('#data tbody tr')].filter(tr=>tr.cells.length>1); return r.length===10 && r.every(tr=>tr.cells[0].textContent.trim()==='West')})()",
           show = "document.querySelectorAll('#data tbody tr').length")),
    L4 = {
      gd = if (is_shiny && impl == "shiny_a") "#plot img" else "#plot .nsewdrag"
      bounds = if (impl == "shiny_a") {
        "(()=>{const v=Shiny.shinyapp.$inputValues; const k=Object.keys(v).find(k=>k.startsWith('brush')); const b=v[k]; return b?[b.xmin,b.xmax,b.ymin,b.ymax]:null})()"
      } else {
        "(()=>{const g=document.querySelector('#plot.js-plotly-plot')||document.querySelector('#plot .js-plotly-plot'); const s=(g.layout.selections||[])[0]; return s?[Math.min(s.x0,s.x1),Math.max(s.x0,s.x1),Math.min(s.y0,s.y1),Math.max(s.y0,s.y1)]:null})()"
      }
      expect = sprintf("(()=>{const b=%s; if(!b) return -1; const c=%s; return c.filter(r=>r.wt>=b[0]&&r.wt<=b[1]&&r.mpg>=b[2]&&r.mpg<=b[3]).map(r=>r.name).sort().join('|')})()", bounds, cars_js)
      shown = "[...document.querySelectorAll('#selected tbody tr')].filter(tr=>tr.cells.length>=4).map(tr=>tr.cells[0].textContent.trim()).sort().join('|')"
      dl = if (is_shiny) {
        "fetch(document.getElementById('download').href).then(r=>r.text())"
      } else {
        "(async()=>{window.__b=[]; const o=URL.createObjectURL; URL.createObjectURL=b=>{window.__b.push(b); return o.call(URL,b)}; document.getElementById('download').click(); await new Promise(r=>setTimeout(r,300)); return await window.__b[0].text()})()"
      }
      csv_ok = sprintf("(async()=>{const t=(await %s).trim().split(/\\r?\\n/); const e=%s; const names=t.slice(1).map(l=>l.split(',')[0].replace(/\"/g,'')).sort().join('|'); return t[0].replace(/\"/g,'').startsWith('name,wt,mpg,hp') && names===e})()", dl, expect)
      list(
        list(name = "initial 0 selected + scatter", pred = sprintf("%s==='0 selected' && document.querySelector('%s')", txt("#n"), gd), show = txt("#n")),
        list(name = "mouse brush -> count and table match bounds", drag = gd,
             pred = sprintf("(()=>{const e=%s; if (e===-1||e==='') return false; return %s===e.split('|').length+' selected' && %s===e})()", expect, txt("#n"), shown),
             show = sprintf("[%s, %s, JSON.stringify(%s)].join(' ; ')", txt("#n"), expect, bounds)),
        list(name = "download CSV = selection", pred = csv_ok, show = dl))
    },
    L5 = {
      edit = switch(impl,
        shiny_a = "(()=>{const td=document.querySelectorAll('#a-table tbody tr')[0].cells[2]; $(td).trigger('dblclick'); const i=td.querySelector('input'); i.value='100'; $(i).trigger('blur'); return 1})()",
        shiny_b = "(()=>{$('#a-stock_1').val(100).trigger('change'); return 1})()",
        html_a = "(()=>{const c=document.querySelector('#a-table td[data-i=\"0\"][data-k=\"stock\"]'); c.textContent='100'; c.dispatchEvent(new Event('input',{bubbles:true})); return 1})()",
        html_b = "(()=>{const i=document.querySelector('#a-table input[data-row=\"0\"][data-key=\"stock\"]'); i.value='100'; i.dispatchEvent(new Event('input',{bubbles:true})); return 1})()")
      list(
        list(name = "initial module values + total",
             pred = sprintf("%s==='Stock value: %s' && %s==='Stock value: %s' && %s==='Total stock value: %s' && document.querySelectorAll('#a-table tbody tr').length===8",
                            txt("#a-value"), exp_l5_init[1], txt("#b-value"), exp_l5_init[2], txt("#total"), exp_l5_init[3]),
             show = sprintf("[%s,%s,%s].join(' ; ')", txt("#a-value"), txt("#b-value"), txt("#total"))),
        list(name = "edit A row 1 stock=100 -> A value + total", act = edit,
             pred = sprintf("%s==='Stock value: %s' && %s==='Total stock value: %s'", txt("#a-value"), exp_l5_edit[1], txt("#total"), exp_l5_edit[2]),
             show = sprintf("[%s,%s].join(' ; ')", txt("#a-value"), txt("#total"))))
    })
}

# ---------- revision-specific steps (G2_REVISED=1; run on a_revised/) ----------
REVISED = identical(Sys.getenv("G2_REVISED"), "1")
top_avg = sprintf("%.2f", mean(sales$price[sales$region == agg$region[1]]))
low_a = paste("Low stock:", paste(inv_a$product[inv_a$stock < 50], collapse = ", "))
rev_steps = function(level, impl) switch(level,
  L1 = list(list(name = "rev: Avg price column", pred = sprintf("[...document.querySelectorAll('table thead th')].some(t=>t.textContent.trim()==='Avg price') && [...document.querySelectorAll('table tbody tr')][0].cells[4].textContent.trim()==='%s'", top_avg),
                 show = "[...document.querySelectorAll('table tbody tr')][0].textContent")),
  L2 = list(list(name = "rev: orange bars (plotly) / plot present (image)",
                 pred = "(()=>{const g=document.getElementById('chart'); return g.data ? JSON.stringify(g.data[0].marker||{}).includes('darkorange') || [...document.querySelectorAll('#chart .point path')].some(p=>getComputedStyle(p).fill.includes('255, 140, 0')) : !!document.querySelector('#chart img')})()",
                 show = "JSON.stringify((document.getElementById('chart').data||[{}])[0].marker)")),
  L3 = list(list(name = "rev: Orders value box", pred = sprintf("%s==='%s'", txt("#vb_orders"), format(sum(sales$region == "West"), big.mark = ",")), show = txt("#vb_orders"))),
  L4 = list(list(name = "rev: cyl column in table and CSV",
                 pred = sprintf("(async()=>{const r=[...document.querySelectorAll('#selected tbody tr')].filter(tr=>tr.cells.length>=5); const t=(await %s).trim().split(/\\r?\\n/); return r.length>0 && t[0].replace(/\"/g,'')==='name,wt,mpg,hp,cyl'})()",
                                if (startsWith(impl, "shiny")) "fetch(document.getElementById('download').href).then(r=>r.text())" else "(async()=>{window.__b=[]; const o=URL.createObjectURL; URL.createObjectURL=b=>{window.__b.push(b); return o.call(URL,b)}; document.getElementById('download').click(); await new Promise(r=>setTimeout(r,300)); return await window.__b[0].text()})()"),
                 show = "[...document.querySelectorAll('#selected tbody tr')].length")),
  L5 = list(list(name = "rev: low-stock line", pred = sprintf("%s==='%s'", txt("#a-low"), low_a), show = txt("#a-low"))))

# ---------- run ----------
stopifnot(http_ok(sprintf("http://127.0.0.1:%d/data/inv_a.json", static_port)))
port = 18300L
out = list()
for (level in paste0("L", 1:5)) for (impl in IMPLS) {
  if (!is.null(only) && !(level %in% only)) next
  is_shiny = startsWith(impl, "shiny")
  f = file.path(APPS, level, paste0(impl, if (is_shiny) ".R" else ".html"))
  t0 = Sys.time()
  if (is_shiny) {
    parse_ok = static_check(f)
    port = port + 1L
    app = launch_shiny(f, port)
    url = sprintf("http://127.0.0.1:%d/", port)
  } else {
    html = readLines(f, warn = FALSE)
    parse_ok = if (any(grepl("</html>", html, fixed = TRUE))) "ok" else "no </html>"
    page = sprintf("%s_%s.html", level, impl)
    writeLines(localise(html), file.path(site, page))
    url = sprintf("http://127.0.0.1:%d/%s", static_port, page)
  }
  h200 = http_ok(url)
  r = if (h200) session_run(url, c(steps_for(level, impl), if (REVISED) rev_steps(level, impl)), file.path(shots, sprintf("%s_%s.png", level, impl))) else NULL
  log_err = character()
  if (is_shiny) {
    app$proc$kill()
    lg = readLines(app$log, warn = FALSE)
    log_err = grep("^(Warning: )?Error", lg, value = TRUE)
  }
  all_ok = identical(parse_ok, "ok") && h200 && !is.null(r) && all(r$steps$ok) &&
    length(r$js_errors) == 0 && r$output_errors == 0 && length(log_err) == 0
  cat(sprintf("%s %-8s parse=%s http200=%s steps=%s js_err=%d out_err=%d log_err=%d => %s (%.1fs)\n",
              level, impl, parse_ok, h200, if (is.null(r)) "-" else paste0(sum(r$steps$ok), "/", nrow(r$steps)),
              if (is.null(r)) 0L else length(r$js_errors), if (is.null(r)) 0L else as.integer(r$output_errors),
              length(log_err), if (all_ok) "PASS" else "FAIL", as.numeric(Sys.time() - t0, units = "secs")))
  if (!is.null(r) && !all(r$steps$ok)) print(r$steps[!r$steps$ok, ])
  if (!is.null(r) && length(r$js_errors)) cat("   js errors:", r$js_errors, "\n")
  if (length(log_err)) cat("   log:", head(log_err, 3), sep = "\n   ")
  out[[length(out) + 1]] = data.frame(level, impl, pass = all_ok)
}
static$kill()
chrome$close()
res = do.call(rbind, out)
cat(sprintf("\nPASS %d of %d apps\n", sum(res$pass), nrow(res)))
