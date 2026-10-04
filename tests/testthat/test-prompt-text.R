# P07 Task 1: the verbatim texts (architecture 7.3-7.4 as amended; contract 9.3; G4 3.6).
# The byte-for-byte checks read the specification under dev/, which is excluded from the
# package build, so they skip under R CMD check and run with devtools::test().

spec_lines = function(...) {
  p = test_path("..", "..", "dev", ...)
  if (!file.exists(p)) skip("dev/ is not available (built package)")
  readLines(p, encoding = "UTF-8", warn = FALSE)
}

# Lines strictly between the first line equal to `open` at or after `from` and the next `close`.
between = function(x, open, close, from = 1L) {
  a = which(x == open)
  a = a[a >= from][1]
  b = which(x == close)
  b = b[b > a][1]
  x[(a + 1L):(b - 1L)]
}

# The ```text block of architecture 7.3 (the composed system prompt).
spec_system_prompt = function() {
  a = spec_lines("spec", "03-architecture.md")
  i = grep("^### 7.3 The system prompt", a)
  between(a, "```text", "```", from = i)
}

test_that("P07's section texts equal architecture 7.3 byte for byte", {
  sp = spec_system_prompt()
  sec = function(name) between(sp, paste0("<", name, ">"), paste0("</", name, ">"))
  j = function(x) paste(x, collapse = "\n")
  expect_identical(prompt_text("preamble"), sp[1])
  expect_identical(prompt_text("r_performance"), j(sec("r_performance")))
  expect_identical(prompt_text("modes"), j(sec("modes")))
  expect_identical(prompt_text("context"), j(sec("context")))
  rs = sec("r_session")
  expect_length(rs, 11L)
  core = j(c(rs[1:4], "{{fragments}}", rs[10:11]))
  expect_identical(prompt_text("r_session"), core)
  tl = sec("tools")
  expect_identical(prompt_text("tools_footer"), tl[length(tl)])
  ru = sec("rules")
  expect_identical(paste0("- ", prompt_text("rules_closing")), ru[(length(ru) - 2L):length(ru)])
})

test_that("mode blocks and non-interactive suffixes equal architecture 7.4 and contract 9.3", {
  a = spec_lines("spec", "03-architecture.md")
  i = grep("^### 7.4 Mode blocks", a)
  for (nm in c("plan", "manual", "edits", "auto")) {
    k = which(a == sprintf("<mode name=\"%s\">", nm))
    k = k[k > i][1]
    expect_identical(prompt_text(paste0("mode_", nm)), a[k + 1L], label = nm)
  }
  c4 = paste(spec_lines("spec", "04-interface-contract.md"), collapse = " ")
  flat = gsub("\\s+", " ", c4)
  # Anchored on the contract's backticks, so a truncated suffix does not pass as a substring.
  tick = function(x) paste0("`", x, "`")
  expect_true(grepl(tick(prompt_text("noninteractive_stop")), flat, fixed = TRUE))
  expect_true(grepl(tick(prompt_text("noninteractive_manual")), flat, fixed = TRUE))
  deny = sub("so actions that need approval stop the run.",
             "so actions that need approval are refused.", prompt_text("noninteractive_stop"),
             fixed = TRUE)
  expect_identical(prompt_text("noninteractive_deny"), deny)
  expect_true(grepl("the second clause reads `so actions that need approval are refused.`", flat,
                    fixed = TRUE))
})

test_that("minimal variants and the extended r_performance equal contract 9.3", {
  c4 = spec_lines("spec", "04-interface-contract.md")
  k = grep("^`preamble`, minimal variant:", c4)
  expect_identical(prompt_text("preamble_short"), c4[k + 3L])
  k = grep("^`rules`, minimal preset:", c4)
  expect_identical(paste0("- ", prompt_text("rules_minimal")), c4[(k + 4L):(k + 5L)])
  k = grep("^`r_performance`, extended preset", c4)
  full = between(c4, "<r_performance>", "</r_performance>", from = k)
  # IC-67: no shipped text mentions str(; the one clause that does is dropped
  full = sub("; str() makes the next in-place edit of a large object copy it.", ".", full,
             fixed = TRUE)
  expect_identical(prompt_text("r_performance_full"), paste(full, collapse = "\n"))
  flat = gsub("\\s+", " ", paste(c4, collapse = " "))
  upd = sprintf(prompt_text("section_updated"), "<name>", "<section>")
  expect_identical(upd, "Updated system prompt section \"<name>\":\n\n<section>")
  expect_true(grepl("`Updated system prompt section \"<name>\":\\n\\n<section>`", flat,
                    fixed = TRUE))
  expect_true(grepl(paste0("`", sprintf(prompt_text("section_removed"), "<name>"), "`"), flat,
                    fixed = TRUE))
})

test_that("the compaction request and checkpoint texts equal G4 section 3.6", {
  g4 = spec_lines("research", "G4-context-assembly-caching-compaction.md")
  k = which(g4 == "<compaction_request>")[1]
  expect_identical(prompt_text("compaction_request"), paste(g4[k:(k + 11L)], collapse = "\n"))
  k = grep("^<checkpoint n=\"1\"", g4)[1]
  expect_identical(prompt_text("checkpoint_intro"), g4[k + 1L])
  # Anchored on G4's string quotes (trailing space included), not a bare substring.
  quoted = paste0("\"", prompt_text("checkpoint_continue"), "\"")
  expect_true(any(grepl(quoted, g4, fixed = TRUE)))
})

test_that("texts are ASCII and never mention str( (IC-67)", {
  for (nm in names(prompt_texts())) {
    x = prompt_texts()[[nm]]
    expect_false(any(grepl("[^\\x01-\\x7f]", x, perl = TRUE)), label = nm)
    expect_false(any(grepl("(^|[^A-Za-z0-9_.])str\\(", x)), label = nm)
  }
})

test_that("the r_session core carries exactly one fragments marker on its own line", {
  lines = strsplit(prompt_text("r_session"), "\n", fixed = TRUE)[[1]]
  expect_identical(sum(lines == "{{fragments}}"), 1L)
  expect_identical(lines[length(lines)],
                   paste0("- Never call q(), quit(), readline() or menu(), and do not install, ",
                          "update or remove packages unless the user asked."))
})

test_that("unknown texts are internal errors", {
  expect_error(prompt_text("nope"), class = "gptr_error_internal")
  # A name that is not one string is unknown too (not a positional or recursive lookup).
  expect_error(prompt_text(1L), class = "gptr_error_internal")
  expect_error(prompt_text(c("preamble", "modes")), class = "gptr_error_internal")
})

test_that("front ends have model-facing labels", {
  expect_identical(prompt_front_end_label("rstudio"), "interactive console (RStudio)")
  expect_identical(prompt_front_end_label("rscript"), "Rscript")
  expect_identical(prompt_front_end_label("unknown"), "R session")
})
