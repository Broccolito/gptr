# P28 Task 28: live dogfood of the peter() console (D-242..D-245) in terminal R under tmux.
#
#   GPTR_LIVE_TESTS=true Rscript --vanilla dev/dogfood/p28-console.R <route> <scenario> [<out>]
#
# route: claude-cli, codex, ollama/<model>, gpt or claude (live_setup()'s m$gpt and m$claude, from
#   the file GPTR_LIVE_SETUP names; keys go through gptr_env() only), or fake (a slow fake model).
# scenario: S1 (steer while thinking, while streaming, during an r call), S2 (Tab follow-up), S3
#   (typing as an approval arrives), S4 (take-back), S5 (completion), S6 (Ctrl-C, a), S7 (a
#   sub-agent's ask with a draft, a steer at the sub-agent), S8-nocolor, S8-dumb, S8-clocale,
#   S8-cols50, S8-pipe, S10 (Ctrl-C beside 2 x nproc busy processes, GPTR_DOGFOOD_REPEAT times),
#   or all.
# gptr comes from GPTR_DOGFOOD_LIB, else .libPaths(). Each run is terminal R in a private tmux
# server at 100x32, keys sent one at a time 40 ms apart, with gptr's settings in temporary R_USER_*
# folders (HOME stays real, so the CLIs keep their sign-ins). It writes <out>/<route>-<scenario>/:
# panes/ (each moment's capture-pane -e -N), screen.ans and screen.txt (the whole history),
# events.tsv (console events, each request's roles and relays), project/session.R (the recording),
# replay/replay.txt (a copy of the project sourcing it with GPTR_REPLAY=replay and no model) and
# result.tsv.

if (nzchar(Sys.getenv("GPTR_DOGFOOD_INNER"))) {
  # the R session under test, which the driver starts with source(<this file>)
  .dogfood = local({
    dir = Sys.getenv("GPTR_DOGFOOD_INNER")
    lib = Sys.getenv("GPTR_DOGFOOD_LIB")
    if (nzchar(lib)) .libPaths(c(lib, .libPaths()))
    suppressPackageStartupMessages(library(gptr))
    route = Sys.getenv("GPTR_DOGFOOD_ROUTE")
    if (route %in% c("gpt", "claude")) {
      setup = new.env()
      sys.source(Sys.getenv("GPTR_LIVE_SETUP"), setup)
      route = setup$live_setup(ollama = FALSE)[[route]]
    }
    if (startsWith(route, "ollama/")) invisible(gptr_models(provider = "ollama", refresh = TRUE))
    if (identical(route, "fake")) {
      text = paste(rep("A slow answer about fuel economy, streamed a few words at a time.", 20L),
                   collapse = " ")
      route = gptr_fake_provider(function(req) list(text = text, chunk = 6L, gap = 0.05))
    }
    gptr_config(egress = list(`claude-cli` = "ack", codex = "ack", versa = "ack",
                              `versa-bedrock` = "ack"), .scope = "user")
    gptr_trust(getwd(), TRUE)
    gptr_doc(file.path(getwd(), "session.R"), format = "transcript")
    grDevices::pdf(NULL)
    log = function(...) {
      x = gsub("[\t\r\n]+", " ", substr(as.character(c(...)), 1L, 2000L))
      cat(sprintf("%.3f\t%s\n", as.numeric(Sys.time()), paste(x, collapse = "\t")),
          file = file.path(dir, "events.tsv"), append = TRUE)
    }
    text_of = function(m) paste(unlist(lapply(m$content, function(b) b$text)), collapse = " ")
    watch = function(peter) {
      on = function(name, f) {
        peter$on(name, function(event, ctx) {
          try(f(event, ctx), silent = TRUE)
          NULL
        })
      }
      kinds = character()
      on("input", function(e, ctx) log("input", e$source, e$text))
      on("agent_start", function(e, ctx) log("agent_start"))
      on("agent_end", function(e, ctx) log("agent_end", e$status))
      # each request's roles, the relays since its last user message, and its user-role steers
      on("before_request", function(e, ctx) {
        m = ctx$session$messages
        roles = vapply(m, function(x) x$role %||% "?", "")
        ops = m[roles == "operator" & seq_along(m) > max(0L, which(roles == "user"))]
        steers = Filter(function(x) identical(x$source, "steer"), m)
        log("request", paste(roles, collapse = ","),
            paste(vapply(ops, text_of, ""), collapse = " | "),
            paste(vapply(steers, text_of, ""), collapse = " | "))
      })
      on("message_start", function(e, ctx) kinds <<- character())
      on("message_update", function(e, ctx) {
        if (!e$kind %in% kinds) log("delta", e$kind)
        kinds <<- union(kinds, e$kind)
      })
      on("tool_execution_start", function(e, ctx) log("tool_start", e$tool_name, e$input$code))
      on("tool_execution_end", function(e, ctx) log("tool_end", e$tool_name, isTRUE(e$is_error)))
      on("permission_request", function(e, ctx) log("permission", e$tool))
      on("queue_update", function(e, ctx) log("queue", e$op, e$which, e$text))
    }
    list(route = route, mode = Sys.getenv("GPTR_DOGFOOD_MODE"), watch = watch, log = log)
  })
  fuel = mtcars[, c("mpg", "wt", "cyl", "gear")]
  .dogfood$session = peter(model = .dogfood$route, mode = .dogfood$mode,
                           extensions = .dogfood$watch, .stdin = !interactive())
  .dogfood$log("left")
  cat("DOGFOOD DONE\n")
  quit(save = "no")
}

# ---- the driver ------------------------------------------------------------------------------

tmux = function(d, ...) {
  processx::run("tmux", c("-S", d$sock, ...), error_on_status = FALSE)$stdout
}
plain = function(x) gsub("\033\\[[0-9;?]*[A-Za-z]|\033\\][^\a]*\a|\r", "", x)
lines_of = function(x) strsplit(x, "\n", fixed = TRUE)[[1L]]
now = function() as.numeric(Sys.time())

driver = function(dir, sock) {
  d = new.env()
  d$dir = dir
  d$sock = sock
  d$seen = 0L
  d$n = 0L
  d$steers = list()
  d$results = data.frame(check = character(), ok = logical(), detail = character())
  d$history = function() {
    lines_of(tmux(d, "capture-pane", "-p", "-J", "-S", "-", "-E", "-", "-t", "dog"))
  }
  d$visible = function() lines_of(tmux(d, "capture-pane", "-p", "-J", "-t", "dog"))
  d$snap = function(label) {
    Sys.sleep(0.4)
    d$n = d$n + 1L
    ans = tmux(d, "capture-pane", "-p", "-e", "-N", "-t", "dog")
    writeLines(ans, file.path(dir, "panes", sprintf("%02d-%s.ans", d$n, label)), sep = "")
    invisible(lines_of(plain(ans)))
  }
  d$key = function(k) {
    tmux(d, "send-keys", "-t", "dog", k)
    Sys.sleep(0.04)
    now()
  }
  d$type = function(text) {
    for (ch in strsplit(text, "")[[1L]]) {
      # tmux reads a lone ; as its command separator
      tmux(d, "send-keys", "-t", "dog", "-l", "--", if (ch == ";") "\\;" else ch)
      Sys.sleep(0.04)
    }
    now()
  }
  d$events = function() {
    f = file.path(dir, "events.tsv")
    if (!file.exists(f)) return(character())
    readLines(f, warn = FALSE, encoding = "UTF-8")
  }
  # Wait for the next event line matching re (after the last one waited for); its time, or NA
  d$wait_event = function(re, timeout = 300) {
    t0 = now()
    repeat {
      ev = d$events()
      hit = which(grepl(re, sub("^[^\t]*\t", "", ev), perl = TRUE))
      hit = hit[hit > d$seen]
      if (length(hit)) {
        d$seen = hit[1L]
        return(as.numeric(sub("\t.*", "", ev[hit[1L]])))
      }
      if (now() - t0 > timeout) {
        d$check(paste("event", re), FALSE, "timed out")
        return(NA_real_)
      }
      Sys.sleep(0.1)
    }
  }
  d$count = function(re) sum(grepl(re, d$history(), perl = TRUE))
  # Wait until more screen lines match re than `before` (those now); the time it showed, or NA
  d$wait_screen = function(re, timeout = 60, before = d$count(re)) {
    t0 = now()
    repeat {
      if (d$count(re) > before) return(now())
      if (now() - t0 > timeout) {
        d$check(paste("screen", re), FALSE, "timed out")
        return(NA_real_)
      }
      Sys.sleep(0.1)
    }
  }
  d$check = function(name, ok, detail = "") {
    d$results[nrow(d$results) + 1L, ] = list(name, isTRUE(ok), paste(detail, collapse = " "))
  }
  d$prompt = function(text) {
    d$type(text)
    d$key("Enter")
    d$wait_event("^input\t", 30)
  }
  d$steer = function(text, label = "steer") {
    d$type(text)
    d$snap(paste0(label, "-draft"))
    t = d$key("Enter")
    row = d$snap(paste0(label, "-queued"))
    d$steers[[length(d$steers) + 1L]] = list(text = text, t = t, label = label,
                                             row = tail(row[nzchar(trimws(row))], 2L))
    t
  }
  # Events after the last one waited for
  d$new_events = function() {
    ev = d$events()
    ev[seq_along(ev) > d$seen]
  }
  # Type text a key every 0.25 s until done(), or with empty = TRUE type x and erase it again;
  # the last key's time, with the text typed as `typed`
  d$drip = function(text, done, empty = FALSE, timeout = 300) {
    t0 = now()
    last = NA_real_
    keys = strsplit(text, "")[[1L]]
    typed = ""
    while (!done() && now() - t0 < timeout) {
      if (empty) {
        d$type("x")
        Sys.sleep(0.21)
        last = d$key("BSpace")
      } else if (length(keys)) {
        last = d$type(keys[1L])
        typed = paste0(typed, keys[1L])
        keys = keys[-1L]
      }
      Sys.sleep(0.21)
    }
    structure(last, typed = typed)
  }
  d$asked = function(re = "\\tpermission\\t") function() any(grepl(re, d$new_events()))
  d$idle = function(timeout = 300) {
    d$wait_event("^agent_end", timeout)
    t0 = now()
    while (now() - t0 < 30) {
      v = d$visible()
      v = v[nzchar(trimws(v))]
      if (length(v) && grepl("^peter(\\[[a-z]+\\])?> ", v[length(v)])) break
      Sys.sleep(0.2)
    }
  }
  d$exit = function() {
    d$key("C-u")
    d$type("/exit")
    d$key("Enter")
  }
  d
}

# ---- scenarios -------------------------------------------------------------------------------

scenarios = list(
  S1 = list(mode = "auto", run = function(d) {
    d$prompt(paste("First write three short paragraphs on why heavier cars use more fuel. Then",
                   "call the r tool once with cor(fuel$mpg, fuel$wt) and report the value."))
    d$wait_event("^agent_start")
    Sys.sleep(0.3)
    d$steer("steer A: end with ALPHA", "thinking")
    d$wait_event("^delta\ttext")
    Sys.sleep(0.3)
    d$steer("steer B: two decimals", "streaming")
    d$idle()
    d$snap("idle-1")
    d$prompt("Call the r tool once with this code: Sys.sleep(8); nrow(fuel)")
    d$wait_event("^tool_start\tr")
    Sys.sleep(1)
    d$steer("steer C: say BRAVO", "during-r")
    d$idle()
    d$snap("idle-2")
  }),
  S2 = list(mode = "auto", run = function(d) {
    d$prompt("Write a 400-word essay on fuel economy, in plain prose, no tools.")
    d$wait_event("^agent_start")
    Sys.sleep(0.3)
    d$type("what is 2 + 2? one word")
    d$snap("follow-up-draft")
    d$key("Tab")
    d$snap("follow-up-queued")
    d$idle()
    d$check("follow-up sent as the next prompt",
            !is.na(d$wait_event("^input\t[a-z]+\twhat is 2 \\+ 2", 30)))
    d$idle()
    d$snap("idle")
    ev = d$events()
    d$check("two runs", sum(grepl("\tagent_end\t", ev)) == 2L)
    d$check("never relayed", !any(grepl("\trequest\t.*\t.*2 \\+ 2", ev)))
  }),
  S3 = list(mode = "manual", run = function(d) {
    ask = "\\? Allow r"
    n = d$count(ask)
    d$prompt("Use the r tool to run exactly: x3 = summary(fuel$mpg); x3")
    last = d$drip("draft three stays here", d$asked())
    draft = attr(last, "typed")
    t = d$wait_screen(ask, 60, n)
    d$check("the ask waits 3 s after the last key of a draft", t - last >= 2.9,
            sprintf("%.1f s, draft '%s'", t - last, draft))
    row = d$snap("ask-with-draft")
    d$check("the ask says the draft is kept",
            any(grepl(paste("draft kept, back after your answer ·", draft), row, fixed = TRUE)))
    d$type("y")
    d$key("Enter")
    row = d$snap("approved")
    d$check("the draft is back", any(grepl(paste("›", draft), row, fixed = TRUE)))
    d$idle()
    row = d$snap("idle-with-draft")
    d$check("the draft waits at the prompt", any(grepl(paste(">", draft), row, fixed = TRUE)))
    d$key("C-u")
    n = d$count(ask)
    d$prompt("Use the r tool to write fuel to fuel.csv in the current folder with write.csv().")
    last = d$drip("", d$asked(), empty = TRUE)
    t = d$wait_screen(ask, 60, n)
    d$check("the ask waits 1 s after the last key", t - last >= 0.9 && t - last < 2.9,
            sprintf("%.1f s", t - last))
    d$snap("ask")
    d$wait_event("^permission\tr")
    n = d$count(ask)
    d$type("n use tempdir()")
    d$key("Enter")
    d$snap("denied")
    d$wait_event("^permission\tr")
    d$wait_screen(ask, 60, n)
    d$snap("ask-again")
    d$check("the retry uses tempdir()",
            grepl("tempdir", tail(grep("\ttool_start\tr\t", d$events(), value = TRUE), 1L)))
    d$type("y")
    d$key("Enter")
    d$idle()
    d$snap("idle")
  }),
  S4 = list(mode = "auto", run = function(d) {
    d$prompt(paste("Think carefully, step by step, about how weight, cylinders and gears each",
                   "change fuel economy. Then write three sentences and call the r tool once with",
                   "mean(fuel$mpg)."))
    d$wait_event("^agent_start")
    one = d$type("s1: weight")
    d$key("Enter")
    d$type("s2: cylinders")
    d$key("Enter")
    d$key("Up")
    d$snap("taken-back")
    for (i in 1:9) d$key("BSpace")
    d$type("gears")
    d$snap("edited")
    d$steers = list(list(text = "s1: weight", t = one, label = "one"),
                    list(text = "s2: gears", t = d$key("Enter"), label = "two"))
    d$snap("requeued")
    d$idle()
    d$snap("idle")
    d$check("the taken-back text never reaches the model",
            !any(grepl("cylinders", grep("\trequest\t", d$events(), value = TRUE))))
  }),
  S5 = list(mode = "auto", run = function(d) {
    tries = c(plain = "check the summ", at_obj = "@fu", at_dir = "@da", peter = "peter$",
              at_col = "@fuel$m", slash = "/mo", skill = "/skill:", bang = "!summ")
    want = c(plain = "> check the summ *$", at_obj = "@fuel", at_dir = "@data/",
             peter = "peter\\$[a-z]", at_col = "@fuel\\$mpg", slash = "/mod", skill = "fuel-check",
             bang = "!summary")
    for (nm in names(tries)) {
      d$type(tries[[nm]])
      d$key("Tab")
      d$key("Tab")
      row = d$snap(paste0("complete-", nm))
      d$check(paste("completion", nm), any(grepl(want[[nm]], row)) &&
                (nm != "plain" || !any(grepl("summary", row))), tail(row[nzchar(row)], 1L))
      d$key("C-u")
      Sys.sleep(0.3)
    }
  }),
  S6 = list(mode = "auto", run = function(d) {
    d$prompt("Write a 600-word story about an old car, in plain prose, no tools.")
    d$wait_event("^agent_start")
    Sys.sleep(0.3)
    d$type("steer six: red car")
    d$key("Enter")
    d$type("draft six")
    d$snap("draft")
    n = d$count("\\? Paused")
    t = d$key("C-c")
    p = d$wait_screen("\\? Paused", 10, n)
    d$check("Paused within 1 s", p - t < 1, sprintf("%.2f s", p - t))
    d$snap("paused")
    n = d$count("kept in history")
    d$type("a")
    d$key("Enter")
    d$wait_screen("kept in history", 60, n)
    row = d$snap("aborted")
    d$check("both are kept", any(grepl("kept in history.*steer six: red car.*draft six", row)),
            tail(row[nzchar(trimws(row))], 2L))
    d$key("Up")
    up1 = d$snap("up-1")
    d$key("Up")
    up2 = d$snap("up-2")
    d$check("Up recalls both", any(grepl("> draft six *$", up1)) &&
              any(grepl("> steer six: red car *$", up2)))
  }),
  S7 = list(mode = "manual", run = function(d) {
    ask = "^\\s*\\? .*[Aa]llow r\\?"
    n = d$count(ask)
    d$prompt(paste0("Run exactly this with the r tool: k = peter(\"Use the r tool to run ",
                    "m = mean(fuel$mpg), then reply with m.\"); k$text"))
    d$wait_screen(ask, 300, n)
    d$snap("parent-ask")
    n = d$count(ask)
    d$type("y")
    d$key("Enter")
    d$wait_screen("sub-agent .* started", 120)
    keys = strsplit("steer seven: say DONE at the end", "")[[1L]]
    while (length(keys) && d$count(ask) == n) {
      d$type(keys[1L])
      keys = keys[-1L]
      Sys.sleep(0.21)
    }
    d$wait_screen(ask, 300, n)
    row = d$snap("child-ask")
    d$check("the sub-agent's ask keeps the draft", any(grepl("draft kept", row)))
    d$type("y")
    d$key("Enter")
    d$type(paste(keys, collapse = ""))
    d$snap("child-approved")
    d$steers[[1L]] = list(text = "steer seven: say DONE at the end", t = d$key("Enter"),
                          label = "at-sub-agent")
    d$snap("at-sub-agent-queued")
    d$idle()
    d$snap("idle")
  })
)
s8 = function(env = character(), cols = 100L) {
  list(mode = "auto", env = env, cols = cols, run = function(d) {
    d$prompt(paste("In three short sentences, say what @fuel holds. Then call the r tool once with",
                   "Sys.sleep(5); nrow(fuel)."))
    d$wait_event("^agent_start")
    Sys.sleep(0.3)
    d$steer("steer eight: also say how many columns", "steer")
    d$idle()
    d$snap("idle")
  })
}
scenarios$`S8-nocolor` = s8(c(NO_COLOR = "1"))
scenarios$`S8-dumb` = s8(c(TERM = "dumb"))
scenarios$`S8-clocale` = s8(c(LANG = "C", LC_ALL = "C"))
scenarios$`S8-cols50` = s8(cols = 50L)
scenarios$`S8-pipe` = list(mode = "auto", pipe = c(
  "In one sentence, say what @fuel holds.", "Call the r tool once with nrow(fuel)."))
scenarios$S10 = list(mode = "auto", run = function(d) {
  burn = lapply(seq_len(2L * parallel::detectCores()), function(i) {
    processx::process$new("yes", stdout = NULL, cleanup = TRUE)
  })
  on.exit(for (p in burn) p$kill(), add = TRUE)
  for (i in seq_len(as.integer(Sys.getenv("GPTR_DOGFOOD_REPEAT", "3")))) {
    d$prompt("Write a 600-word essay about fuel economy, in plain prose, no tools.")
    d$wait_event("^delta\ttext")
    d$type("draft ten")
    n = d$count("\\? Paused")
    t = d$key("C-c")
    p = d$wait_screen("\\? Paused", 10, n)
    d$check(paste("Paused within 1 s, run", i), p - t < 1, sprintf("%.2f s", p - t))
    d$type("c")
    d$key("Enter")
    d$idle()
    v = d$visible()
    v = v[nzchar(trimws(v))]
    d$check(paste("the draft waits at the idle prompt, run", i),
            grepl("^peter(\\[[a-z]+\\])?> draft ten *$", v[length(v)]), v[length(v)])
    n = d$count("kept in history")
    t = d$key("C-c")
    p = d$wait_screen("kept in history", 10, n)
    d$check(paste("kept in history within 1 s, run", i), p - t < 1, sprintf("%.2f s", p - t))
  }
})

# ---- one run ---------------------------------------------------------------------------------

project_files = function(proj) {
  dir.create(file.path(proj, "data"), recursive = TRUE)
  dir.create(file.path(proj, ".gptr", "skills", "fuel-check"), recursive = TRUE)
  writeLines(c("# Fuel study", "Goal: show how fuel economy falls with weight."),
             file.path(proj, "notes.md"))
  utils::write.csv(mtcars[1:5, 1:3], file.path(proj, "data", "cars.csv"))
  writeLines(c("---", "name: fuel-check", "description: Check the fuel data before plotting.",
               "---", "Check that fuel has the columns mpg and wt."),
             file.path(proj, ".gptr", "skills", "fuel-check", "SKILL.md"))
}

run_scenario = function(route, name, out, script) {
  sc = scenarios[[name]]
  dir = file.path(out, paste0(gsub("[^A-Za-z0-9.]+", "-", route), "-", name))
  unlink(dir, recursive = TRUE)
  dir.create(file.path(dir, "panes"), recursive = TRUE)
  proj = file.path(dir, "project")
  project_files(proj)
  user = file.path(dir, "user", c("config", "data", "cache"))
  for (u in user) dir.create(u, recursive = TRUE)
  env = c(R_USER_CONFIG_DIR = user[1L], R_USER_DATA_DIR = user[2L], R_USER_CACHE_DIR = user[3L],
          GPTR_PROJECT_ROOT = proj, GPTR_LIVE_TESTS = "true", GPTR_DOGFOOD_INNER = dir,
          GPTR_DOGFOOD_ROUTE = route, GPTR_DOGFOOD_MODE = sc$mode,
          GPTR_DOGFOOD_LIB = Sys.getenv("GPTR_DOGFOOD_LIB"),
          GPTR_LIVE_SETUP = Sys.getenv("GPTR_LIVE_SETUP"),
          R_LIBS_USER = Sys.getenv("R_LIBS_USER"), LANG = "en_US.UTF-8")
  env[names(sc$env)] = sc$env
  cmd = "exec R --vanilla --quiet"
  if (!is.null(sc$pipe)) {
    cmd = paste("printf '%s\\n'", paste(shQuote(c(sc$pipe, "/exit")), collapse = " "),
                "| Rscript --vanilla", shQuote(script))
  }
  writeLines(c(paste0("cd ", shQuote(proj)), paste0("export ", names(env), "=", shQuote(env)), cmd),
             file.path(dir, "run.sh"))
  d = driver(dir, tempfile("tm"))
  t0 = now()
  tmux(d, "-f", "/dev/null", "new-session", "-d", "-s", "dog", "-x", sc$cols %||% 100L,
       "-y", 32L, paste("/bin/sh", shQuote(file.path(dir, "run.sh"))))
  # an error in a scenario still ends the server and the R under test
  on.exit(tmux(d, "kill-server"), add = TRUE)
  tmux(d, "set", "-g", "remain-on-exit", "on")
  tmux(d, "set", "-g", "history-limit", "50000")
  if (is.null(sc$pipe)) {
    d$wait_screen("^> $", 30)
    d$type(sprintf("source(%s)", deparse(script)))
    d$key("Enter")
    d$wait_screen("^peter(\\[[a-z]+\\])?> ", 120)
    d$snap("banner")
    sc$run(d)
    d$exit()
  }
  done = d$wait_screen("DOGFOOD DONE", 300, before = 0L)
  ans = tmux(d, "capture-pane", "-p", "-e", "-S", "-", "-E", "-", "-t", "dog")
  writeLines(ans, file.path(dir, "screen.ans"), sep = "")
  screen = lines_of(plain(tmux(d, "capture-pane", "-p", "-J", "-S", "-", "-E", "-", "-t", "dog")))
  writeLines(screen, file.path(dir, "screen.txt"))
  tmux(d, "kill-server")
  d$check("the console was left", !is.na(done), sprintf("%.0f s", now() - t0))
  ev = d$events()
  requests = grep("\trequest\t", ev)
  for (s in d$steers) {
    take = grep(paste0("\tqueue\ttake\tsteer\t", s$text), ev, fixed = TRUE)
    t = as.numeric(sub("\t.*", "", ev[take[1L]]))
    d$check(paste("delivered:", s$label), length(take) == 1L,
            sprintf("%.1f s after Enter", t - s$t))
    d$check(paste("shown once at delivery:", s$label),
            sum(screen %in% paste(c("›", ">", ">>"), s$text)) == 1L)
    # The next request carries it (IC-55): as a relay, or as a user-role steer when the run's start
    # poll took it, before the run's first request (which a CLI route's probe delays by about 1 s)
    at = c(take, length(ev) + 1L)[1L]
    start = max(0L, grep("\tagent_start$", ev[seq_len(at)]))
    early = !any(requests > start & requests < at)
    f = strsplit(ev[requests[requests > at][1L]], "\t", fixed = TRUE)[[1L]]
    d$check(paste("relayed:", s$label), if (early) grepl(s$text, f[5L], fixed = TRUE) else
              grepl(paste("while you were working:", s$text), f[4L], fixed = TRUE),
            if (early) "a user-role steer at the run's start")
  }
  check_recording(d, file.path(proj, "session.R"), env)
  write.table(d$results, file.path(dir, "result.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
  cat(basename(dir), sprintf("  %s %s %s", ifelse(d$results$ok, "ok  ", "FAIL"), d$results$check,
                             d$results$detail), sep = "\n")
  invisible(d$results)
}

# The recording parses, keeps every steer, and replays with GPTR_REPLAY=replay and no model
check_recording = function(d, path, env) {
  if (!file.exists(path)) return(d$check("recorded", FALSE, "no session.R"))
  rec = readLines(path, encoding = "UTF-8")
  d$check("the recording parses", !inherits(try(parse(text = rec), silent = TRUE), "try-error"))
  for (s in d$steers) {
    d$check(paste("recorded steer:", s$label), any(grepl(s$text, rec, fixed = TRUE)))
  }
  # a copy of the project (its cache holds the answers of nested peter() calls), with user folders
  # of its own: no model is configured and no key is loaded
  rep = file.path(dirname(dirname(path)), "replay")
  for (u in c("config", "data", "cache")) dir.create(file.path(rep, "user", u), recursive = TRUE)
  file.copy(dirname(path), rep, recursive = TRUE)
  code = c("fuel = mtcars[, c('mpg', 'wt', 'cyl', 'gear')]", "grDevices::pdf(NULL)",
           "source('session.R')", "cat('REPLAY DONE\\n')")
  user = file.path(rep, "user")
  res = processx::run("Rscript", c("--vanilla", "-e", paste(code, collapse = "; ")),
                      wd = file.path(rep, "project"), error_on_status = FALSE,
                      stderr_to_stdout = TRUE, env = c(
                        "current", GPTR_REPLAY = "replay", R_LIBS_USER = env[["R_LIBS_USER"]],
                        R_USER_CONFIG_DIR = file.path(user, "config"),
                        R_USER_DATA_DIR = file.path(user, "data"),
                        R_USER_CACHE_DIR = file.path(user, "cache"),
                        GPTR_PROJECT_ROOT = file.path(rep, "project"),
                        R_LIBS = env[["GPTR_DOGFOOD_LIB"]]))
  writeLines(res$stdout, file.path(rep, "replay.txt"))
  d$check("replays without a model", res$status == 0L && grepl("REPLAY DONE", res$stdout),
          tail(lines_of(res$stdout), 1L))
}

if (!nzchar(Sys.getenv("GPTR_DOGFOOD_INNER")) && !interactive()) {
  args = commandArgs(trailingOnly = TRUE)
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true") || length(args) < 2L) {
    stop("Usage: GPTR_LIVE_TESTS=true Rscript --vanilla dev/dogfood/p28-console.R <route> ",
         "<scenario> [<out>]")
  }
  script = normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
  out = if (length(args) > 2L) args[[3L]] else tempfile("p28-dogfood-")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  out = normalizePath(out)
  todo = if (identical(args[[2L]], "all")) names(scenarios) else args[[2L]]
  for (name in todo) run_scenario(args[[1L]], name, out, script)
}
