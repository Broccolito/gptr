# tests/testthat/test-copy-gateway.R (Task 11: create)
# Fresh-process tracemem rows for every gateway entry point (G3 t5 and its verification log;
# IC-41; architecture 6.4). Each row runs its setup (creating the 40 MB `big`), starts
# tracemem(big), runs the gateway code and then the user's next in-place edit `big[1] = 0`: a
# `tracemem[` line after the action means gptr kept a reference and the edit copied the whole
# object. Rows with `in_run_edit = TRUE` also edit `big` inside the run, through an `r` tool call
# of the helper's fake provider (IC-41). expect_no_copy() (P01) skips on CRAN and without
# capabilities("profmem").

# The child loads gptr with export_all = FALSE, so it sees only the exports. Until Task 12
# exports gptr(), gptr_step() and gptr_wait() (D-113 item 3), the child takes them from the
# namespace, as test-copy-s1.R does for gptr(); once they are exported these lines do nothing.
copy_exports = sprintf(
  paste0("if (!('%1$s' %%in%% getNamespaceExports('gptr'))) ",
         "%1$s = get('%1$s', envir = asNamespace('gptr'))"),
  c("gptr", "gptr_step", "gptr_wait"))

# M1 has no `r` tool (P10 adds it): a stand-in that evaluates the code where the run evaluates.
copy_r_tool = paste0(
  "r_tool = gptr_tool('r', 'Run R code (test stand-in).', ",
  "parameters = list(type = 'object', properties = list(code = list(type = 'string'))), ",
  "execute = function(input, ctx) { eval(parse(text = input$code), envir = ctx$envir); 'ok' })")

# A tool that designates `big` as the run's value with gptr_return() (IC-48), and a fake that
# calls it once.
copy_keep_tool = c(
  paste0("keep = gptr_tool('keep', 'Designates big.', parameters = list(type = 'object', ",
         "properties = structure(list(), names = character())), ",
         "execute = function(input, ctx) { gptr_return(big); 'kept' })"),
  paste0("fake_keep = gptr_fake_provider(list(list(tool = 'keep', ",
         "input = structure(list(), names = character())), 'done'), name = 'keep')"))

# Every row: `big`, a fake provider answering 'ok', no permission gate (no `mode` policy exists
# before P11 and the gate fails closed, IC-53) and the stand-in r tool.
copy_setup = c(
  "big = runif(5e6)",
  copy_exports,
  "fake = gptr_fake_provider(list('ok'))",
  "options(gptr.unsafe_no_permissions = TRUE)",
  copy_r_tool)

# label = list(extra setup, action, in_run_edit)
copy_rows = list(
  "top level: gptr('describe', big)" =
    list(character(), "s = gptr('describe', big, model = fake)", FALSE),
  "data-first pipe: big |> gptr('describe')" =
    list(character(), "s = big |> gptr('describe', model = fake)", FALSE),
  "continuation with context: s |> gptr('b', big)" =
    list(character(), "s = gptr('a', model = fake); s |> gptr('b', big)", FALSE),
  "named context: gptr('describe', data = big)" =
    list(character(), "s = gptr('describe', data = big, model = fake)", FALSE),
  "wrapper with forwarded dots: w('describe', big)" =
    list(character(), "w = function(...) gptr(...); s = w('describe', big, model = fake)", FALSE),
  "session created inside a function: f(big)" =
    list(character(), "f = function(d) gptr('describe', d, model = fake); s = f(big)", FALSE),
  "wrapper with a registered model name: model = fake" =
    list("invisible(gptr_register(fake))",
         "f = function(d) gptr('describe', d, model = fake); s = f(big)", FALSE),
  "wrapper with model = if (TRUE) fake else haiku" =
    list(character(),
         "f = function(d) gptr('describe', d, model = if (TRUE) fake else haiku); s = f(big)",
         FALSE),
  "wrapper with tools = c(grep, write) and an interpolated prompt" =
    list(character(),
         paste0("f = function(d) { cl = 3; gptr('cluster {cl}', d, model = fake, ",
                "tools = c(grep, write)) }; s = f(big)"), FALSE),
  "$value read, printed and assigned (gptr_return(big) by name)" =
    list(copy_keep_tool,
         paste0("s = gptr('designate big', model = fake_keep, tools = list(keep)); ",
                "print(head(s$value, 2)); x = s$value; rm(x)"), FALSE),
  "print, summary, str and format of a session" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake); print(s); invisible(summary(s)); ",
                "str(s); invisible(format(s))"), FALSE),
  "gptr_fork(s) and a fork turn" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake, envir = globalenv()); ",
                "f = gptr_fork(s); f |> gptr('read big')"), FALSE),
  "saveRDS(s) and readRDS()" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake); p = tempfile(); saveRDS(s, p); ",
                "r = readRDS(p)"), FALSE),
  ".run = FALSE, then gptr_step()" =
    list(character(), "s = gptr('describe', big, model = fake, .run = FALSE); gptr_step(s)",
         FALSE),
  ".run = FALSE, then gptr_wait() on a list" =
    list(character(), "a = gptr('one', big, model = fake, .run = FALSE); gptr_wait(list(a))",
         FALSE),
  "gptr_return(big) outside a run" =
    list(character(), "invisible(gptr_return(big))", FALSE),
  "tool code run in a function-frame home (G3 verification log)" =
    list(paste0("fake = gptr_fake_provider(list(list(tool = 'r', ",
                "input = list(code = 'n = length(d)')), 'done'))"),
         "f = function(d) gptr('describe', d, model = fake, tools = list(r_tool)); s = f(big)",
         FALSE),
  "in-run edit: gptr('x', big) (IC-41)" =
    list(character(), "s = gptr('x', big, model = fake, tools = list(r_tool))", TRUE),
  "in-run edit: big |> gptr('x') (IC-41)" =
    list(character(), "s = big |> gptr('x', model = fake, tools = list(r_tool))", TRUE),
  "in-run edit: s |> gptr('x', big) (IC-41)" =
    list(c("fake0 = gptr_fake_provider(list('ok'), name = 'fake0')",
           "s = gptr('a', model = fake0, tools = list(r_tool))"),
         "s |> gptr('x', big, model = fake)", TRUE))

for (label in names(copy_rows)) {
  row = copy_rows[[label]]
  test_that(paste("no copy of big after", label), {
    expect_no_copy(c(copy_setup, row[[1L]]), row[[2L]], label = label, in_run_edit = row[[3L]])
  })
}
