# tests/testthat/test-risk-forms.R -- forms gptr_risk() reads since review round 5 (FIX-27,
# FIX-36): each is read, or the limit ?gptr_security names stays as it was

test_that("a variable a registered provider reads is control (review round 5)", {
  root = local_project()
  lv = function(code) gptr_risk(code, root = root)
  py = function(code) gptr_risk(paste0("peter$py(", deparse(code), ")"), root = root)
  # Bedrock's base URL, the key pair a bedrock-converse provider signs with, vercel-jev's key
  for (v in c("AWS_REGION", "AWS_DEFAULT_REGION", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
              "AWS_SESSION_TOKEN", "AI_GATEWAY_API_KEY", "aws_region", "AZURE_OPENAI_ENDPOINT",
              "TYPESAFE_API_KEY", "VLLM_API_KEY")) {
    r = lv(paste0("Sys.setenv(", v, " = 'x')"))
    expect_identical(r$level, 4L, label = v)
    expect_true("control" %in% r$categories, label = v)
    expect_identical(py(paste0("import os\nos.environ['", v, "'] = 'x'"))$level, 4L, label = v)
  }
  # a provider a person registers: its key and address are gptr's configuration too
  expect_identical(lv("Sys.setenv(CORP_LLM_TOKEN = 'x')")$level, 2L)
  off = gptr_register(gptr_provider("corp-r5", api = "openai-completions", base_url = NULL,
                                    auth = "CORP_LLM_TOKEN",
                                    compat = list(base_url_env = "CORP_LLM_HOST",
                                                  base_url_template = "https://{value}/v1")))
  withr::defer(off())
  expect_identical(lv("Sys.setenv(CORP_LLM_TOKEN = 'x')")$level, 4L)
  expect_identical(lv("Sys.unsetenv('CORP_LLM_HOST')")$level, 4L)
  # neighbours: a variable no provider reads stays a session change
  for (v in c("TZ", "MY_VAR", "JAVA_HOME", "AWS_PROFILE_NOTE")) {
    expect_identical(lv(paste0("Sys.setenv(", v, " = 'x')"))$level, 2L, label = v)
  }
})

test_that("cmd /c and PowerShell -Command run every word after them (review round 5)", {
  root = local_project()
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  f = file.path(out, "marker.txt")
  for (cmd in c(paste("cmd /c del", f), paste("cmd.exe /C rd /s /q", out),
                paste("cmd /k del", f), paste("cmd /r del", f), paste("CMD /S /C del", f),
                paste("pwsh -NoProfile -Command Remove-Item", f),
                paste("powershell -command Remove-Item -Recurse", out),
                paste("pwsh -c Remove-Item", f),
                # PowerShell takes any abbreviation of -Command, after - or /
                paste("pwsh -Comm Remove-Item", f), paste("powershell -co Remove-Item", f),
                paste("pwsh /Command Remove-Item", f))) {
    expect_identical(lv(paste0("system(", deparse(cmd), ")")), 4L, label = cmd)
  }
  expect_identical(lv(paste0("processx::run('cmd', c('/c', 'del', ", deparse(f), "))")), 4L)
  sh = registry_get("tool", "sh")
  expect_identical(as.integer(sh$risk(list(cmd = paste("cmd /c del", f), wd = "."), NULL)$level),
                   4L)
  # neighbours: the command in the project keeps its level; sh -c still reads one word
  expect_identical(lv("system('cmd /c del marker.txt')"), 3L)
  expect_identical(lv("system('cmd /c dir')"), 3L)
  expect_identical(lv(paste("system('sh -c ls", f, "')")), 3L)
  expect_identical(lv("system('pwsh -NoProfile -File x.ps1')"), 3L)
})

test_that("callr::run() and sys::exec_*() are read as processx::run() is (review round 5)", {
  root = local_project()
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  args = paste0("('rm', c('-f', ", deparse(file.path(out, "marker.txt")), "))")
  for (fn in c("processx::run", "callr::run", "sys::exec_wait", "sys::exec_internal",
               "sys::exec_background")) {
    expect_identical(lv(paste0(fn, args)), 4L, label = fn)
    # neighbours: a command in the project reads as processx::run()'s does
    expect_identical(lv(paste0(fn, "('ls')")), lv("processx::run('ls')"), label = fn)
    expect_identical(lv(paste0(fn, "('rm', c('-f', 'marker.txt'))")), 3L, label = fn)
  }
  expect_identical(lv(paste0("callr::run('rm', c('-f', 'marker.txt'), wd = ", deparse(out), ")")),
                   4L)
  # a command the code computes is a dynamic row, as processx::run()'s is
  expect_identical(lv("sys::exec_wait(cmd)"), 3L)
})

test_that("eval(quote(x)) is read as x, and xfun::in_dir() as with_dir() (review round 5)", {
  root = local_project()
  dir.create(file.path(root, "sub"))
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  o = deparse(out)
  for (code in c(paste0("eval(quote(setwd(", o, ")))"),
                 paste0("rlang::eval_bare(quote(setwd(", o, ")))"),
                 paste0("eval(base::quote(setwd(", o, ")))"),
                 paste0("base::eval(envir = e, quote(unlink(", deparse(file.path(out, "m")), ")))"),
                 paste0("rlang::eval_tidy(quote(withr::local_dir(", o, ")))"),
                 paste0("xfun::in_dir(", o, ", unlink('marker.txt'))"), "xfun::in_dir(d, x)")) {
    expect_identical(lv(code), 4L, label = code)
  }
  # neighbours: in the project, eval()'s own row (3) as evalq()'s; a quote() alone is data
  expect_identical(lv("eval(quote(setwd('sub')))"), lv("evalq(setwd('sub'))"))
  expect_identical(lv("eval(quote(unlink('marker.txt')))"), 3L)
  expect_identical(lv("xfun::in_dir('sub', x)"), 2L)
  expect_identical(lv(paste0("q = quote(setwd(", o, "))")), 2L)
})

test_that("env -C runs its command in that directory, read as a cd (review round 5)", {
  root = local_project()
  dir.create(file.path(root, "sub"))
  # with "/": sh reads a backslash in a command line as an escape
  out = path_norm(withr::local_tempdir(tmpdir = dirname(tempdir())))
  sh = registry_get("tool", "sh")
  level = function(cmd) as.integer(sh$risk(list(cmd = cmd, wd = "."), NULL)$level)
  for (cmd in c("env -C %s rm -f marker.txt", "env --chdir=%s rm -f marker.txt",
                "env --chdir %s rm -f marker.txt", "env -i -C %s rm -f marker.txt",
                "env -C%s rm -f marker.txt", "env -C %s sh -c 'rm -f marker.txt'")) {
    cmd = sprintf(cmd, out)
    expect_identical(level(cmd), 4L, label = cmd)
  }
  expect_identical(level(c("env", "-C", out, "rm", "-f", "marker.txt")), 4L)
  expect_identical(level(paste("env -C", out, "ls")), 1L)
  # Windows' spelling: peter$sh() runs such a line in Git Bash there when it is installed, which
  # drops the backslashes, so it reads as an escape the classifier does not model (3)
  expect_identical(level(paste("env -C", chartr("/", "\\", out), "ls")), 3L)
  # neighbours: in the project as before
  expect_identical(level("env -C sub rm -f marker.txt"), 3L)
  expect_identical(level("env -C sub ls"), 0L)
  # `~` and $HOME there are the home directory, as after a cd (a home outside tempdir())
  home = withr::local_tempdir(tmpdir = dirname(tempdir()))
  withr::local_envvar(HOME = home, USERPROFILE = home)
  dir.create(file.path(home, "other"))
  for (cmd in c("env -C ~/other rm -f m", "env -C ~ rm -f m", "env -C $HOME rm -f m",
                "env -C ${HOME}/other rm -f m", "git -C ~/other rm -f m", "git -C ~ rm -f m",
                "cd ~/other && rm -f m")) {
    expect_identical(level(cmd), 4L, label = cmd)
  }
  # neighbours: a directory the shell computes reads as a cd to it does
  expect_identical(level("env -C \"$X\" rm -f m"), level("cd \"$X\" && rm -f m"))
})

test_that("a Python variable name it cannot read in an environment write is control (round 5)", {
  root = local_project()
  py = function(code) gptr_risk(paste0("peter$py(", deparse(code), ")"), root = root)$level
  for (code in c("os.environ['\\x48OME'] = d", "os.environ['H' 'OME'] = d",
                 "os.environ['H'\n  'OME'] = d", "os.environb[b'\\x48OME'] = b'd'",
                 "os.environ['\\N{LATIN CAPITAL LETTER H}OME'] = d", "os.putenv('H' 'OME', d)",
                 "k = 'HO' + 'ME'\nos.environ[k] = d", "del os.environ[k]",
                 "os.environ.pop(k, None)", "os.environ[f'{k}'] = d", "os.unsetenv(k)",
                 # a subscript is read to its closing bracket, and every augmented assignment
                 "os.environ[keys[0]] = d", "os.environ[d['k']] = v", "os.environ[a[b[0]]] = v",
                 "os.environ['HOME' if ']' else 'TZ'] = v", "del os.environ[a[b[0]]]",
                 "os.environ[k] %= v", "os.environ[k] **= v")) {
    expect_identical(py(paste0("import os\n", code)), 4L, label = code)
  }
  # neighbours: a plain literal name that controls nothing, and reads, as before
  for (code in c("os.environ['TZ'] = 'UTC'", "os.environ[\"TZ\"] = 'UTC'",
                 "os.environ.update(TZ = 'UTC')", "os.putenv(b'TZ', b'UTC')",
                 "os.environ['a]b'] = 'UTC'", "os.environ['TZ'] = d[0]", "os.environ['TZ'] %= v")) {
    expect_identical(py(paste0("import os\n", code)), 3L, label = code)
  }
  expect_identical(py("import os\nx = os.environ[k]"), 2L)
  expect_identical(py("import os\nx = os.environ[keys[0]]"), 2L)
  expect_identical(py("import os\nok = os.environ[keys[0]] == d"), 2L)
  # a name that only ends in environ is not os.environ
  for (code in c("my_environ[k] = 1", "del my_environ[k]", "my_environ.pop(k)",
                 "my_environ.clear()")) {
    expect_identical(py(code), py(sub("my_environ", "d", code, fixed = TRUE)), label = code)
  }
})

test_that("a link to a path outside the project is level 4, as ln's (review round 5)", {
  root = local_project()
  dir.create(file.path(root, "sub"))
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  o = deparse(out)
  for (code in c(paste0("file.symlink(", o, ", 'lnk')"),
                 paste0("file.link(", deparse(file.path(out, "a")), ", 'lnk')"),
                 paste0("Sys.junction(", o, ", 'lnk')"),
                 paste0("file.symlink(to = 'lnk', from = ", o, ")"),
                 paste0("d = ", o, "; file.symlink(d, 'lnk')"))) {
    expect_identical(lv(code), 4L, label = code)
  }
  expect_identical(lv(paste0("system('ln -s ", out, " lnk')")), 4L)
  # neighbours: a link to a path in the project or the session's tempdir() is a write
  for (code in c("file.symlink('sub', 'lnk')", "file.symlink(tempdir(), 'lnk')",
                 "file.link('sub/a', 'b')")) {
    expect_identical(lv(code), 2L, label = code)
  }
  # fs::link_create() as R matches it while fs is loaded, and as written while it is not, where
  # each unnamed argument may be the path it writes (so new_path is named beside tempdir())
  matched = risk_args
  for (fs_loaded in c(TRUE, FALSE)) {
    local_mocked_bindings(risk_args = function(e, fn, pkg) {
      if (!identical(fn, "link_create")) return(matched(e, fn, pkg))
      matched(e, if (fs_loaded) function(path, new_path, symbolic = TRUE) NULL else fn,
              if (fs_loaded) pkg else NA)
    })
    for (code in c(paste0("fs::link_create(", o, ", 'lnk')"),
                   paste0("fs::link_create(new_path = 'lnk', path = ", o, ")"))) {
      expect_identical(lv(code), 4L, label = paste(code, "with fs loaded", fs_loaded))
    }
    for (code in c("fs::link_create('sub', 'lnk')",
                   "fs::link_create(tempdir(), new_path = 'lnk')")) {
      expect_identical(lv(code), 2L, label = paste(code, "with fs loaded", fs_loaded))
    }
  }
})

test_that("getwd() and setwd()'s value are the working directory (review round 5)", {
  root = local_project()
  dir.create(file.path(root, "data"))
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  # the save-and-restore idioms stay in the project
  for (code in c("owd = setwd('data'); x = list.files(); setwd(owd)",
                 "owd = getwd(); setwd('data'); setwd(owd)",
                 "setwd(file.path(getwd(), 'data'))",
                 paste("original_wd = getwd(); data_wd = file.path(original_wd, 'data');",
                       "setwd(data_wd); x = list.files(); setwd(original_wd)"),
                 "a = setwd('data'); setwd(a); b = setwd('data'); setwd(b)",
                 "owd = setwd(tempdir()); setwd(owd)")) {
    expect_identical(lv(code), 2L, label = code)
  }
  # out of the project, or a directory the code computes, as before
  for (code in c("setwd(o)", "setwd(file.path(getwd(), '..', '..'))",
                 "setwd(tempdir()); setwd(file.path(getwd(), '..'))",
                 "withr::with_dir('data', setwd(file.path(getwd(), '..', '..')))",
                 "if (x) owd = setwd('data'); setwd(owd)")) {
    expect_identical(lv(code), 4L, label = code)
  }
  # from a folder in the project: getwd() is where the code has moved R to
  withr::local_dir(file.path(root, "data"))
  expect_identical(lv("setwd(file.path(getwd(), '..'))"), 2L)
  expect_identical(lv("setwd(tempdir()); setwd(file.path(getwd(), '..'))"), 4L)
  expect_identical(lv("setwd(tempdir()); owd = setwd('x'); setwd(file.path(owd, '..'))"), 4L)
  # a working directory outside the project is read as such
  withr::local_dir(out)
  expect_identical(lv("owd = setwd(file.path(getwd(), 'x')); setwd(owd)"), 4L)
})

test_that("a getwd() or setwd() the code or the session binds is one the code computes (merge)", {
  root = local_project()
  dir.create(file.path(root, "data"))
  lv = function(code, envir = NULL) gptr_risk(code, envir = envir, root = root)$level
  for (code in c("getwd = function() '~'; setwd(getwd())",
                 "getwd = function() '~'; owd = getwd(); setwd('data'); setwd(owd)",
                 "getwd = function() '~'; setwd(file.path(getwd(), 'data'))",
                 "setwd = function(d) '~'; owd = setwd('x'); base::setwd(owd)")) {
    expect_identical(lv(code), 4L, label = code)
  }
  e = new.env()
  e$getwd = function() "~"
  expect_identical(lv("owd = getwd(); setwd('data'); setwd(owd)", e), 4L)
  # base's, and a name bound to a value that is no function, which R passes over
  for (code in c("setwd(getwd())", "owd = getwd(); setwd('data'); setwd(owd)",
                 "getwd = 1; setwd(getwd())")) {
    expect_identical(lv(code), 2L, label = code)
  }
})

test_that("auto and yolo run the setwd() save-and-restore idiom unasked (review round 5)", {
  skip_on_cran()
  root = local_project()
  dir.create(file.path(root, "data"))
  writeLines("x", file.path(root, "data", "a.csv"))
  ui = local_scripted_ui(list())
  for (mode in c("auto", "yolo")) {
    code = "owd = setwd('data'); x = list.files(); setwd(owd)"
    fake = local_fake_provider(list(fake_tool("r", code = code), "Done."),
                               name = paste0("owd-", mode))
    peter("List the data.", model = fake, mode = mode, envir = new.env())
  }
  expect_identical(sum(ui$log$method == "permission"), 0L)
  expect_identical(path_norm(getwd()), root)
})

test_that("the yolo notice names moving the working directory out of the project (round 5)", {
  local_gptr_options(quiet = FALSE)
  rm(list = intersect("message:mode_yolo", ls(the$once)), envir = the$once)
  withr::defer(rm(list = intersect("message:mode_yolo", ls(the$once)), envir = the$once))
  expect_message(mode_notice("yolo"), "moving the working directory out of the project",
                 class = "gptr_message_notice")
})

test_that("Sys.junction() writes its `to`, with R's formals or as written, on any host (round 6)", {
  root = local_project()
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  check = function() {
    for (code in c("Sys.junction('sub', '.git/hooks/x')", "Sys.junction('sub', '~/.Rprofile')",
                   "Sys.junction(to = '.gptr/agents', from = 'sub')")) {
      r = gptr_risk(code, root = root)
      expect_identical(list(r$level, "control" %in% r$categories), list(4L, TRUE), label = code)
    }
    expect_identical(lv(paste0("Sys.junction('sub', ", deparse(file.path(out, "x")), ")")), 3L)
    expect_identical(lv(paste0("Sys.junction(", deparse(out), ", 'lnk')")), 4L)
    expect_identical(lv("Sys.junction('sub', 'lnk')"), 2L)
  }
  check()
  # with R's formals, as on Windows, where the function exists
  matched = risk_args
  local_mocked_bindings(risk_args = function(e, fn, pkg) {
    matched(e, if (identical(fn, "Sys.junction")) function(from, to) NULL else fn, pkg)
  })
  check()
})

test_that("sys::exec_*()'s std_out and std_err are files it writes, as processx's (round 6)", {
  root = local_project()
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  for (f in c(file.path(out, "x"), "~/.Rprofile", ".git/config", "x.txt")) {
    px = c(lv(paste0("processx::run('ls', stdout = ", deparse(f), ")")),
           lv(paste0("processx::run('ls', stderr = ", deparse(f), ")")))
    for (fn in c("sys::exec_wait", "sys::exec_background")) {
      sx = c(lv(paste0(fn, "('ls', std_out = ", deparse(f), ")")),
             lv(paste0(fn, "('ls', std_err = ", deparse(f), ")")))
      expect_identical(sx, px, label = paste(fn, f))
    }
  }
  expect_identical(lv(paste0("sys::exec_wait('ls', std_out = ", deparse(file.path(out, "x")), ")")),
                   3L)
  # neighbours: output to R's console or a connection writes no file
  expect_identical(lv("sys::exec_wait('ls', std_out = TRUE)"), lv("processx::run('ls')"))
  expect_identical(lv("sys::exec_wait('ls', std_out = FALSE)"), lv("processx::run('ls')"))
  # nor does a callback written there, whose code is read as any function's (review round 6
  # verification)
  for (f in c("function(x) cat(rawToChar(x))", "\\(x) message(rawToChar(x))")) {
    for (code in c(paste0("sys::exec_wait('ls', std_out = ", f, ")"),
                   paste0("sys::exec_background('ls', std_err = ", f, ")"))) {
      expect_identical(lv(code), lv("sys::exec_wait('ls')"), label = code)
    }
  }
  expect_identical(lv("sys::exec_wait('ls', std_out = function(x) unlink('~/.Rprofile'))"),
                   lv("unlink('~/.Rprofile')"))
})

test_that("a variable the claude and codex CLIs keep is control, as a provider's key (round 6)", {
  root = local_project()
  lv = function(code) gptr_risk(code, root = root)
  py = function(code) gptr_risk(paste0("peter$py(", deparse(code), ")"), root = root)$level
  for (v in c("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "codex_home")) {
    r = lv(paste0("Sys.setenv(", v, " = 'x')"))
    expect_identical(list(r$level, "control" %in% r$categories), list(4L, TRUE), label = v)
    expect_identical(lv(paste0("Sys.unsetenv('", v, "')"))$level, 4L, label = v)
    expect_identical(py(paste0("import os\nos.environ['", v, "'] = 'x'")), 4L, label = v)
  }
  # neighbours: a variable no provider reads stays a session change
  for (v in c("RETICULATE_PYTHON", "CODEX_NOTE", "TZ")) {
    expect_identical(lv(paste0("Sys.setenv(", v, " = 'x')"))$level, 2L, label = v)
  }
})

test_that("paste(), paste0() and file.path() are folded with their arguments as R passes them", {
  root = local_project()
  out = withr::local_tempdir(tmpdir = dirname(tempdir()))
  lv = function(code) gptr_risk(code, root = root)$level
  # paste0() has no `sep` (one more part), `collapse` joins the parts, file.path()'s `fsep` too
  for (code in c("Sys.unsetenv(x = paste0('R_USER_', sep = 'CONFIG_DIR'))",
                 "Sys.unsetenv(x = paste0('R_USER_CONFIG_DIR', collapse = 'x'))",
                 "nm = paste('R_USER_CONFIG_DIR', collapse = 'x'); Sys.unsetenv(nm)",
                 "Sys.unsetenv(file.path('XDG_CONFIG_HOME', fsep = ''))",
                 "Sys.unsetenv(file.path('R_USER', 'CONFIG_DIR', fsep = '_'))",
                 # a collapse is also read as each value a name may hold
                 "n = 'TZ'; if (p) n = 'XDG_CONFIG_HOME'; Sys.unsetenv(paste(n, collapse = ''))")) {
    r = gptr_risk(code, root = root)
    expect_identical(list(r$level, "control" %in% r$categories), list(4L, TRUE), label = code)
  }
  expect_identical(lv("system(paste0('ls', sep = '; rm -rf build'))"),
                   lv("system('ls; rm -rf build')"))
  expect_identical(lv("setwd(paste0('../..', collapse = 'x'))"), 4L)
  expect_identical(lv(paste0("unlink(paste0(", deparse(out), ", collapse = '/x'))")), 4L)
  d = paste0("d = 'x'; if (p) d = ", deparse(out), "; ")
  expect_identical(lv(paste0(d, "unlink(paste0(d, collapse = ''))")), lv(paste0(d, "unlink(d)")))
  # a collapse of literals is only R's value (review round 6 verification)
  for (cmd in c("python3", "R", "bash")) {
    expect_identical(lv(paste0("system(paste(c('", cmd, "', '--version'), collapse = ' '))")),
                     lv(paste0("system('", cmd, " --version')")), label = cmd)
  }
  expect_identical(lv("processx::run(paste(c('python3', '--version'), collapse = ' '))"),
                   lv("processx::run('python3 --version')"))
  # while R's working directory, as a name, may hold several values
  w = "if (p) setwd('sub'); "
  expect_identical(lv(paste0(w, "unlink(paste0(getwd(), collapse = ''))")),
                   lv(paste0(w, "unlink(getwd())")))
  # neighbours: as before
  for (code in c("Sys.unsetenv(x = paste0('T', 'Z'))", "Sys.unsetenv(paste('T', 'Z', sep = ''))",
                 "Sys.unsetenv(c(a = 'TZ'))", "Sys.unsetenv(paste0(c('T', 'Z'), collapse = ''))",
                 "setwd(file.path('data', 'sub'))")) {
    expect_identical(lv(code), 2L, label = code)
  }
  expect_identical(lv("unlink(paste0('a', '.csv'))"), lv("unlink('a.csv')"))
  expect_identical(lv(paste0("unlink(file.path(", deparse(out), ", 'x', fsep = '/'))")), 4L)
})
