# Ported from G6 section 5.2 (test_redact.R): 40 checks on FAKE keys, plus the verification-log
# PGP case. Fake keys are assembled at run time so that no key-shaped literal sits in the sources.
fake_jev = paste0("ts_", "FAKE0000jev0key0for0tests00001")
fake_ant = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
fake_odd = "p@ss w0rd#FAKE!!"
fake_ghp = paste0("gh", "p_", strrep("FAKEfake", 4), "1234")

register_fakes = function() {
  secret_register(fake_jev, "TYPESAFE_API_KEY", "dotenv:jev-key.env")
  secret_register(fake_ant, "ANTHROPIC_API_KEY", "environment")
  secret_register(fake_odd, "DB_PASSWORD", "dotenv:.env")
  invisible(NULL)
}

pattern_cases = function() {
  c(
    openai = paste0("OPENAI_API_KEY=sk-", "proj-FAKEfakeFAKEfakeFAKEfake1234567890abcd"),
    google = paste0("key=AI", "zaFAKEfakeFAKEfakeFAKEfakeFAKEfake123"),
    github = paste("token", fake_ghp, "used"),
    finepat = paste0("github_", "pat_11FAKEFAKE0123456789_abcdefFAKE"),
    slack = paste0("xo", "xb-1234567890-1234567890-FAKEfakeFAKE"),
    hf = paste0("hf", "_FAKEfakeFAKEfakeFAKEfakeFAKEfake12"),
    aws = paste0("AK", "IAFAKEFAKEFAKE2345"),
    jwt = paste0("ey", "JhbGciOiJIUzI1NiJ9.eyJzdWIiOiJGQUtFIn0.FAKEsignatureFAKE"),
    bearer = "Authorization: Bearer FAKEtoken1234567890abcdef",
    urlpw = "postgres://analyst:FAKEpassw0rd@db.example.test:5432/prod",
    named = "MY_SERVICE_TOKEN     FAKEvalue9876543210",
    pem = paste0("-----BEGIN RSA PRIVATE ", "KEY-----\nMIIFAKE\n-----END RSA PRIVATE ", "KEY-----")
  )
}

test_that("registered values and their derived forms are redacted", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  b64 = jsonlite::base64_enc(charToRaw(paste0("user:", fake_jev)))
  b64url = chartr("+/", "-_",
                  gsub("\n", "", jsonlite::base64_enc(charToRaw(paste0("xx", fake_ant)))))
  cases = list(
    plain = paste("key is", fake_jev, "ok"),
    urlenc = paste0("https://x.test/?k=", utils::URLencode(fake_odd, reserved = TRUE)),
    json = as.character(jsonlite::toJSON(list(k = fake_odd), auto_unbox = TRUE)),
    basic = paste("Authorization: Basic", b64),
    b64url = b64url,
    printed = utils::capture.output(print(c(TYPESAFE_API_KEY = fake_jev)))[2]
  )
  for (n in names(cases)) {
    r = redact(cases[[n]], "context")
    leak = grepl(fake_jev, r, fixed = TRUE) || grepl(fake_ant, r, fixed = TRUE) ||
      grepl(fake_odd, r, fixed = TRUE) || grepl(substr(b64, 9, 30), r, fixed = TRUE) ||
      grepl(substr(b64url, 9, 40), r, fixed = TRUE)
    expect_false(leak, label = paste("value form redacted:", n))
  }
  expect_identical(redact(cases$plain, "persist"), "key is [secret:TYPESAFE_API_KEY] ok")
  expect_identical(redact(cases$json, "persist"), "{\"k\":\"[secret:DB_PASSWORD]\"}")
})

test_that("the 12 rules redact their shapes and leave near misses alone", {
  vault_reset()
  withr::defer(vault_reset())
  pos = pattern_cases()
  for (n in names(pos)) {
    r = redact(pos[[n]], "context")
    rest = gsub("\\[secret:[^]]*\\]", "", r)
    expect_false(grepl("FAKE", rest), label = paste("pattern redacted:", n))
  }
  expect_identical(redact(pos[["bearer"]], "persist"), "Authorization: Bearer [secret:auth-header]")
  expect_identical(redact(pos[["urlpw"]], "persist"),
                   "postgres://analyst:[secret:url-password]@db.example.test:5432/prod")
  expect_identical(redact(pos[["named"]], "persist"),
                   "MY_SERVICE_TOKEN     [secret:MY_SERVICE_TOKEN]")
  neg = c("task-force-management-plan-2026-review-notes",
          "library(sklearn); x = 'sk-learn'",
          "commit 3f2c9a1b7e4d5f6a8b9c0d1e2f3a4b5c6d7e8f9a",
          "id 123e4567-e89b-12d3-a456-426614174000",
          "token = my_token_variable_2",
          "api_key = Sys.getenv(\"OPENAI_API_KEY\")",
          "basic summary_statistics_table",
          "see https://cran.r-project.org/web/packages/httr2/",
          "Bearer tokens are sent in headers",
          "[secret:TYPESAFE_API_KEY]")
  for (x in neg) expect_identical(redact(x, "context"), x)
})

test_that("a PGP private key block is redacted (G6 verification log)", {
  vault_reset()
  withr::defer(vault_reset())
  pgp = paste0("-----BEGIN PGP PRIVATE ", "KEY BLOCK-----\nlQOYBFAKEFAKE\n",
               "-----END PGP PRIVATE ", "KEY BLOCK-----")
  expect_identical(redact(paste("key:", pgp), "persist"), "key: [secret:private-key]")
  lines = strsplit(pgp, "\n", fixed = TRUE)[[1]]
  expect_identical(redact(lines, "persist"), c("[secret:private-key]", "", ""))
})

test_that("redaction is idempotent; the code profile skips NAME=value and rewrites literals", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  all_text = paste(c(paste("key is", fake_jev), pattern_cases()), collapse = "\n")
  r1 = redact(all_text, "persist")
  expect_identical(redact(r1, "persist"), r1)
  code = paste0("hdr = paste('Bearer', tok)\nMY_TOKEN = 'x'\nk = 'sk-",
                "ant-api03-FAKEFAKEFAKEFAKEFAKE'")
  expect_true(grepl("MY_TOKEN = 'x'", redact(code, "code"), fixed = TRUE))
  expect_true(grepl("k = '[secret:anthropic-key]'", redact(code, "code"), fixed = TRUE))
  lit = paste0("k = \"", fake_jev, "\"\nf(k)\n")
  expect_identical(redact(lit, "code"), "k = Sys.getenv(\"TYPESAFE_API_KEY\")\nf(k)\n")
  expect_identical(redact(lit, "persist"), "k = \"[secret:TYPESAFE_API_KEY]\"\nf(k)\n")
})

test_that("user_data redacts values only; NA and attributes survive; invalid UTF-8 never errors", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  x = c(a = paste("v", fake_jev), b = NA, c = "Authorization: Bearer FAKEtoken1234567890abcdef")
  r = redact(x, "user_data")
  expect_identical(names(r), c("a", "b", "c"))
  expect_identical(unname(r), c("v [secret:TYPESAFE_API_KEY]", NA,
                                "Authorization: Bearer FAKEtoken1234567890abcdef"))
  bad = paste0("bin \xff\xfe ", fake_jev)
  rb = redact(bad, "persist")
  expect_false(grepl(fake_jev, rb, fixed = TRUE, useBytes = TRUE))
  expect_error(redact("x", "nope"), class = "gptr_error_invalid_argument")
})

test_that("a later registration is redacted from then on", {
  vault_reset()
  withr::defer(vault_reset())
  late = paste0("FAKE_late_registered_", "secret_42")
  before = redact(paste("value", late), "context")
  secret_register(late, "LATE_KEY", "session")
  after = redact(paste("value", late), "context")
  expect_true(grepl(late, before, fixed = TRUE))
  expect_identical(after, "value [secret:LATE_KEY]")
})

test_that("long secrets (private keys, long tokens) never overflow the PCRE pattern size", {
  vault_reset()
  withr::defer(vault_reset())
  pem = function(i) {
    body = rep(sprintf("MIIEvFAKE%04dFAKEfakeFAKEfakeFAKEfakeFAKEfakeFAKEfakeFAKE", i), 26)
    paste0("-----BEGIN PRIVATE ", "KEY-----\n", paste(body, collapse = "\n"),
           "\n-----END PRIVATE ", "KEY-----")
  }
  for (i in 1:4) secret_register(pem(i), paste0("PEM_KEY_", i), "test")
  huge = paste0(strrep("FAKEhuge", 5000), "end")
  secret_register(huge, "HUGE_TOKEN", "test")
  st = secrets_state()
  expect_true(all(nchar(st$lit_re) <= 16000L))
  expect_gt(length(st$lits_long), 0L)
  expect_identical(redact(paste("a", pem(3), "b", huge, "c"), "persist"),
                   "a [secret:PEM_KEY_3] b [secret:HUGE_TOKEN] c")
  expect_identical(redact(paste0("u=", utils::URLencode(pem(4), reserved = TRUE)), "context"),
                   "u=[secret:PEM_KEY_4]")
  expect_identical(redact(paste0("k = '", huge, "'"), "code"), "k = Sys.getenv(\"HUGE_TOKEN\")")
})

test_that("a PEM block split over a line vector keeps the length and the neighbours", {
  vault_reset()
  withr::defer(vault_reset())
  lines = c("before", paste0("-----BEGIN OPENSSH PRIVATE ", "KEY-----"),
            "b3BlbnNzaC1rZXktdjEAAAAFAKE", "FAKEFAKEFAKE",
            paste0("-----END OPENSSH PRIVATE ", "KEY-----"), "after")
  rl = redact(lines, "context")
  expect_length(rl, length(lines))
  expect_false(any(grepl("FAKE", rl)))
  expect_identical(rl[c(1, 2, 6)], c("before", "[secret:private-key]", "after"))
})

test_that("trees: text and arguments are redacted, opaque replay fields are not", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  blocks = list(
    list(type = "thinking", thinking = paste("I saw", fake_jev),
         signature = paste0("EqQB", fake_ant)),
    list(type = "redacted_thinking", data = paste0("RVhBTVBMRS", fake_jev)),
    list(type = "text", text = paste("done:", fake_jev), text_signature = NULL),
    list(type = "tool_call", id = "call_1", name = "r",
         arguments = list(code = paste0("k = '", fake_jev, "'"))),
    list(type = "thinking", thinking = "", redacted = TRUE, data = paste0("ENC", fake_jev)),
    list(type = "opaque", provider = "openai", api = "openai-responses", model = "m",
         json = paste0("{\"encrypted_content\":\"", fake_jev, "\"}")),
    list(type = "thinking", thinking = "x", redacted = TRUE,
         gptr = list(data = paste0("ENC", fake_jev))),
    list(type = "image", mime = "image/png", data = paste0("iVBORw0KGgo", fake_jev),
         source = "plot")
  )
  msg = list(role = "assistant", content = blocks)
  rt = redact_tree(msg, "persist")
  expect_identical(rt$content[[8]]$data, msg$content[[8]]$data)
  expect_identical(rt$content[[3]]$text, "done: [secret:TYPESAFE_API_KEY]")
  expect_false(grepl(fake_jev, rt$content[[4]]$arguments$code, fixed = TRUE))
  expect_identical(rt$content[[1]]$thinking, "I saw [secret:TYPESAFE_API_KEY]")
  expect_identical(rt$content[[1]]$signature, msg$content[[1]]$signature)
  expect_identical(rt$content[[2]]$data, msg$content[[2]]$data)
  expect_identical(rt$content[[5]]$data, msg$content[[5]]$data)
  expect_identical(rt$content[[6]]$json, msg$content[[6]]$json)
  expect_identical(rt$content[[7]]$gptr$data, msg$content[[7]]$gptr$data)
  expect_true("text_signature" %in% names(rt$content[[3]]))
})

test_that("structural redaction blanks sensitive header values only", {
  vault_reset()
  withr::defer(vault_reset())
  hdr = list(url = "https://api.anthropic.com/v1/messages",
             headers = list(`x-api-key` = "k-not-registered-123",
                            `anthropic-version` = "2023-06-01", Authorization = "Bearer abc"))
  rs = redact_tree(hdr, "persist", structural = TRUE)
  expect_identical(rs$headers$`x-api-key`, "[secret:x-api-key]")
  expect_identical(rs$headers$`anthropic-version`, "2023-06-01")
  expect_identical(rs$headers$Authorization, "[secret:Authorization]")
  expect_identical(rs$url, hdr$url)
  obj = structure(list(text = paste("x", fake_jev)), class = "gptr_tool_result")
  vault_reset()
  secret_register(fake_jev, "TYPESAFE_API_KEY")
  expect_s3_class(redact_tree(obj), "gptr_tool_result")
  expect_identical(redact(list(a = paste("x", fake_jev)))$a, "x [secret:TYPESAFE_API_KEY]")
})

test_that("gptr_redact() validates its arguments and delegates to the redactor", {
  vault_reset()
  withr::defer(vault_reset())
  expect_identical(gptr_redact("Authorization: Bearer abcdef0123456789abcdef"),
                   "Authorization: Bearer [secret:auth-header]")
  expect_identical(gptr_redact(list(a = "postgres://u:FAKEpw99@h/db"))$a,
                   "postgres://u:[secret:url-password]@h/db")
  expect_null(gptr_redact(NULL))
  expect_error(gptr_redact(1), class = "gptr_error_invalid_argument")
  expect_error(gptr_redact("x", "nope"), class = "gptr_error_invalid_argument")
})

test_that("the redaction hook is installed: conditions never carry a registered value", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  expect_identical(redact_hook(paste("k", fake_jev)), "k [secret:TYPESAFE_API_KEY]")
  e = tryCatch(gptr_abort(paste0("HTTP 401: {\"error\":\"invalid x-api-key ", fake_ant, "\"}"),
                          "auth"), error = identity)
  expect_s3_class(e, "gptr_error_auth")
  expect_false(grepl(fake_ant, conditionMessage(e), fixed = TRUE))
})

test_that("ordinary signature and JSON fields never bypass value redaction", {
  vault_reset()
  withr::defer(vault_reset())
  secret_register(fake_jev, "TYPESAFE_API_KEY")
  fields = c("signature", "thinking_signature", "thought_signature", "text_signature",
             "thinkingSignature", "thoughtSignature", "textSignature", "encrypted_content", "json")
  values = stats::setNames(rep(list(fake_jev), length(fields)), fields)
  expected = stats::setNames(rep(list("[secret:TYPESAFE_API_KEY]"), length(fields)), fields)
  expect_identical(redact_tree(values), expected)
  expect_identical(redact_tree(list(metadata = values))$metadata, expected)
})

test_that("generic payload fields cannot spoof replay blocks to hide registered values", {
  vault_reset()
  withr::defer(vault_reset())
  secret_register(fake_jev, "TYPESAFE_API_KEY")
  generic = c("input", "arguments", "raw_arguments", "details", "params", "attrs",
              "headers", "settings", "env")
  for (field in generic) {
    object = stats::setNames(list(list(type = "opaque", json = fake_jev)), field)
    expect_identical(redact_tree(object)[[field]]$json, "[secret:TYPESAFE_API_KEY]")
  }
  block = block_tool_call("c1", "tool", list(type = "thinking", signature = fake_jev),
                          thought_signature = fake_jev)
  redacted = redact_tree(block)
  expect_identical(redacted$thought_signature, fake_jev)
  expect_identical(redacted$arguments$signature, "[secret:TYPESAFE_API_KEY]")
  for (block in list(block_text("x", signature = fake_jev),
                    block_thinking("x", signature = fake_jev))) {
    expect_identical(redact_tree(block)$signature, fake_jev)
  }
})

test_that("unterminated private-key blocks redact every remaining line", {
  vault_reset()
  withr::defer(vault_reset())
  begin = paste0("-----BEGIN PRIVATE ", "KEY-----")
  end = paste0("-----END PRIVATE ", "KEY-----")
  incomplete = c(begin, "FAKE-MIDDLE-ONLY", "FAKE-LAST-LINE")
  expect_identical(redact(incomplete), c("[secret:private-key]", "", ""))
  expect_identical(redact(paste(incomplete, collapse = "\n")), "[secret:private-key]")
  complete = c(paste0("prefix ", begin), "FAKE-BODY", paste0(end, " suffix"), "after")
  expect_identical(redact(complete), c("prefix [secret:private-key]", "", " suffix", "after"))
})

test_that("literal redaction preserves emitted markers without hiding adjacent raw values", {
  vault_reset()
  withr::defer(vault_reset())
  value = paste0("FAKE_", "TOKEN_NAME")
  secret_register(value, value)
  marker = paste0("[secret:", value, "]")
  expect_identical(redact(value, "user_data"), marker)
  expect_identical(redact(marker, "user_data"), marker)
  expect_identical(redact(paste(marker, value), "user_data"), paste(marker, marker))
  expect_identical(redact(paste0(marker, value), "user_data"), paste0(marker, marker))
  expect_identical(redact(paste0("[secret:", value), "user_data"), paste0("[secret:", marker))
  bad = paste0("bin \xff ", marker, " ", value)
  expect_identical(charToRaw(redact(bad, "user_data")),
                   charToRaw(paste0("bin \xff ", marker, " ", marker)))
})

test_that("structural redaction exempts only complete markers and handle displays", {
  vault_reset()
  withr::defer(vault_reset())
  h = secret_register(fake_jev, "TYPESAFE_API_KEY")
  malformed = c("[secret:pretend]FAKE_UNREGISTERED_PASSWORD_TAIL",
                "<secret pretend>FAKE_UNREGISTERED_PASSWORD_TAIL",
                "[secret:unfinished", paste0(format(h), "FAKE_TAIL"))
  for (value in malformed) {
    expect_identical(redact_tree(list(password = value), structural = TRUE)$password,
                     "[secret:password]")
  }
  for (value in c("[secret:password]", format(h))) {
    expect_identical(redact_tree(list(password = value), structural = TRUE)$password, value)
  }
})

test_that("an unknown marker name cannot hide a registered credential", {
  vault_reset()
  withr::defer(vault_reset())
  secret_register(fake_jev, "TYPESAFE_API_KEY")
  forged = paste0("[secret:", fake_jev, "]")
  out = redact(forged, "user_data")
  expect_false(grepl(fake_jev, out, fixed = TRUE))
  expect_identical(redact(out, "user_data"), out)
})


# Streaming chunk invariance (G6 section 5.2 part 6). A fixed LCG, not R's RNG, drives the chunk
# sizes, so the user's .Random.seed is never touched.
lcg_new = function(seed = 42) {
  state = seed
  function(n) {
    out = numeric(n)
    for (i in seq_len(n)) {
      state <<- (1103515245 * state + 12345) %% 2^31
      out[i] = state / 2^31
    }
    out
  }
}

stream_through = function(rs, text, lcg, max_chunk) {
  pieces = character()
  holds = integer()
  pos = 1L
  while (pos <= nchar(text)) {
    k = 1L + floor(lcg(1) * max_chunk)
    pieces = c(pieces, rs$push(substr(text, pos, pos + k - 1L)))
    holds = c(holds, rs$held())
    pos = pos + k
  }
  list(text = paste(c(pieces, rs$flush()), collapse = ""), holds = holds)
}

stream_doc = function() {
  paste0(
    "Here is the configuration I found.\n",
    "TYPESAFE_API_KEY=", fake_jev, "\nThe Anthropic key ", fake_ant, " should never be shown.",
    " Password: ", fake_odd, " (with spaces).\nAuthorization: Bearer FAKEtoken1234567890abcdef\n",
    "A url postgres://analyst:FAKEpassw0rd@db.example.test/prod and a PEM:\n",
    "-----BEGIN PRIVATE ", "KEY-----\nMIIFAKEFAKE\nFAKEFAKE==\n-----END PRIVATE ", "KEY-----\n",
    "task-force-2026 and sk-learn stay. ", fake_ghp, " goes."
  )
}

test_that("a short stream equals whole-text redaction (CRAN-sized)", {
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  text = stream_doc()
  want = redact(text, "stream")
  lcg = lcg_new(7)
  for (trial in 1:10) {
    expect_identical(stream_through(redact_stream("stream"), text, lcg, 30)$text, want)
  }
  expect_false(grepl(fake_ant, want, fixed = TRUE))
})

test_that("streaming equals whole-text redaction over 400 chunkings; no secret prefix leaks", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  text = stream_doc()
  want = redact(text, "stream")
  lcg = lcg_new(42)
  fails = 0L
  leak = FALSE
  holds = integer()
  for (trial in 1:400) {
    got = stream_through(redact_stream("stream"), text, lcg, if (trial <= 200) 9 else 60)
    if (!identical(got$text, want)) fails = fails + 1L
    for (sec in c(fake_jev, fake_ant, fake_odd)) {
      if (grepl(substr(sec, 1, 12), got$text, fixed = TRUE)) leak = TRUE
    }
    holds = c(holds, got$holds)
  }
  expect_identical(fails, 0L)
  expect_false(leak)
  expect_lte(max(holds), 4096L)
})

test_that("1,000 shuffled documents streamed in chunks of 1-200 characters stay invariant", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  frags = c(fake_jev, fake_ant, fake_odd, "Bearer FAKEtok3n4567890abcdefgh",
            "postgres://u:FAKEpw99@h/db",
            paste0("-----BEGIN EC PRIVATE ", "KEY-----\nMHcFAKE\n-----END EC PRIVATE ", "KEY-----"),
            fake_ghp, paste0("AI", "zaFAKEfakeFAKEfakeFAKEfakeFAKEfake123"),
            "task-force-2026", "sk-learn", "The model fit well.",
            paste0(strrep("`", 3), "r\nfit = lm(y ~ x)\n", strrep("`", 3)),
            "{\"k\": \"v\"}", "## Heading", "- bullet", "x |> head()",
            "https://cran.r-project.org/",
            "TOKEN=", "Password:", "-----", "BEGIN", "sk-", "eyJ", "\n")
  lcg = lcg_new(42)
  fails = 0L
  for (trial in 1:1000) {
    ord = order(lcg(length(frags)))
    seps = ifelse(lcg(length(frags)) < 0.5, " ", "\n")
    doc = paste0(frags[ord], seps, collapse = "")
    got = stream_through(redact_stream("stream"), doc, lcg, 200)
    if (!identical(got$text, redact(doc, "stream"))) fails = fails + 1L
  }
  expect_identical(fails, 0L)
})

test_that("the persist profile (NAME=value rule included) is chunk invariant too", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  register_fakes()
  text = paste0(stream_doc(), "\nMY_SERVICE_TOKEN     FAKEvalue9876543210\n",
                "OPENAI_API_KEY=sk-", "proj-FAKEfakeFAKEfakeFAKEfake1234567890abcd\n")
  want = redact(text, "persist")
  lcg = lcg_new(3)
  fails = 0L
  for (trial in 1:200) {
    got = stream_through(redact_stream("persist"), text, lcg, if (trial <= 100) 9 else 60)
    if (!identical(got$text, want)) fails = fails + 1L
  }
  expect_identical(fails, 0L)
})

test_that("a multi-byte character split across chunks is held, not mangled", {
  vault_reset()
  withr::defer(vault_reset())
  rs = redact_stream("stream")
  e_acute = charToRaw("\u00e9")
  first = rs$push(rawToChar(e_acute[1]))
  second = rs$push(paste0(rawToChar(e_acute[2]), " ok"))
  out = paste0(first, second, rs$flush())
  expect_identical(first, "")
  expect_identical(charToRaw(out), charToRaw("\u00e9 ok"))
  expect_identical(rs$push(NULL), "")
  expect_error(redact_stream("nope"), class = "gptr_error_invalid_argument")
})

expect_failed_redaction_stream = function(rs, cnd, limit, sensitive_prefix) {
  expect_s3_class(cnd, "gptr_error_redaction_limit")
  if (!inherits(cnd, "gptr_error_redaction_limit")) return(invisible(NULL))
  expect_identical(cnd$limit, as.integer(limit))
  expect_null(cnd$call)
  expect_length(grepRaw(charToRaw(sensitive_prefix), serialize(cnd, NULL)), 0L)
  expect_identical(rs$held(), 0L)
  expect_error(rs$push("ordinary follow-up"), class = "gptr_error_redaction_limit")
  expect_error(rs$flush(), class = "gptr_error_redaction_limit")
  expect_identical(rs$held(), 0L)
}

test_that("stream overflow fails closed at every split around the default cap (D-010)", {
  vault_reset()
  withr::defer(vault_reset())
  limit = 4096L
  value = paste0("FAKE_LONG_PRIVATE_", strrep("x", limit + 32L))
  secret_register(value, "LONG_TOKEN")
  for (split in (limit - 2L):(limit + 2L)) {
    rs = redact_stream()
    emitted = character()
    cnd = tryCatch({
      emitted = c(emitted, rs$push(substr(value, 1L, split)))
      emitted = c(emitted, rs$push(substring(value, split + 1L)))
      NULL
    }, error = identity)
    expect_failed_redaction_stream(rs, cnd, limit, substr(value, 1L, 16L))
    expect_identical(paste(emitted, collapse = ""), "")
  }
})

test_that("oversized derived credentials and unterminated PEM never emit raw prefixes", {
  vault_reset()
  withr::defer(vault_reset())
  limit = 4096L
  value = paste0("FAKE LONG PRIVATE ", strrep("x", limit + 32L))
  secret_register(value, "LONG_TOKEN")
  pem = paste0("-----BEGIN PRIVATE ", "KEY-----\n", strrep("FAKE_PRIVATE_BODY", 300L))
  for (text in c(utils::URLencode(value, reserved = TRUE), pem)) {
    for (split in c(1L, limit - 1L, limit, limit + 1L)) {
      rs = redact_stream()
      emitted = character()
      cnd = tryCatch({
        emitted = c(emitted, rs$push(substr(text, 1L, split)))
        emitted = c(emitted, rs$push(substring(text, split + 1L)))
        NULL
      }, error = identity)
      expect_failed_redaction_stream(rs, cnd, limit, substr(text, 1L, 16L))
      expect_identical(paste(emitted, collapse = ""), "")
    }
  }
})

test_that("flush also rejects oversized pending candidates and leaves failure latched", {
  vault_reset()
  withr::defer(vault_reset())
  rs = redact_stream()
  pending = paste0("FAKE_PRIVATE_PENDING_", strrep("x", 4100L))
  rs$pending = pending
  cnd = tryCatch(rs$flush(), error = identity)
  expect_failed_redaction_stream(rs, cnd, 4096L, substr(pending, 1L, 16L))
})

test_that("known markers remain unchanged when streamed across arbitrary character boundaries", {
  vault_reset()
  withr::defer(vault_reset())
  value = paste0("FAKE_", "TOKEN_NAME")
  secret_register(value, value)
  text = paste0("before [secret:", value, "] after")
  want = redact(text, "user_data")
  for (split in seq_len(nchar(text) - 1L)) {
    rs = redact_stream("user_data")
    got = paste0(rs$push(substr(text, 1L, split)), rs$push(substring(text, split + 1L)), rs$flush())
    expect_identical(got, want)
  }
})


test_that("invalid byte overflow also clears and permanently stops the stream", {
  vault_reset()
  withr::defer(vault_reset())
  rs = redact_stream()
  chunk = rawToChar(c(as.raw(255), charToRaw(paste0("FAKE_INVALID_", strrep("x", 4096L)))))
  cnd = tryCatch(rs$push(chunk), error = identity)
  expect_failed_redaction_stream(rs, cnd, 4096L, "FAKE_INVALID_")
})

test_that("the streaming hold limit must be a positive finite integer", {
  for (limit in list(NA_real_, Inf, 0, 1.5, 1 + 1i)) {
    withr::local_options(gptr.stream_hold_max = limit)
    expect_error(redact_stream(), class = "gptr_error_invalid_argument")
  }
})


test_that("recorded code replays: exact literals become Sys.getenv(), the rest are flagged", {
  vault_reset()
  withr::defer(vault_reset())
  secret_register(fake_ghp, "GITHUB_PAT", "environment")
  code = c("req = httr2::request('https://api.github.com/user')",
           paste0("req = httr2::req_auth_bearer_token(req, '", fake_ghp, "')"),
           paste0("msg = paste('token:', '", fake_ghp, "')"),
           paste0("hdr = 'Bearer ", fake_ghp, "'"))
  h = code_for_history(code)
  expect_false(grepl(fake_ghp, h, fixed = TRUE))
  expect_true(grepl("req_auth_bearer_token(req, Sys.getenv(\"GITHUB_PAT\"))", h, fixed = TRUE))
  expect_true(grepl("paste('token:', Sys.getenv(\"GITHUB_PAT\"))", h, fixed = TRUE))
  expect_true(grepl("hdr = 'Bearer [secret:GITHUB_PAT]'", h, fixed = TRUE))
  expect_true(startsWith(h, "# gptr: block needs secrets that are not recorded\n"))
  expect_identical(attr(h, "needs"), "GITHUB_PAT")
  expect_silent(parse(text = h))
  expect_identical(as.character(code_for_history(h)), as.character(h))
})

test_that("code without secrets passes through unchanged and unflagged", {
  vault_reset()
  withr::defer(vault_reset())
  code = "fit = lm(mpg ~ wt, data = mtcars)\nsummary(fit)"
  h = code_for_history(code)
  expect_identical(as.character(h), code)
  expect_identical(attr(h, "needs"), character())
  expect_error(code_for_history(1), class = "gptr_error_invalid_argument")
})

test_that("a secret whose name is not a variable name becomes a flagged marker", {
  vault_reset()
  withr::defer(vault_reset())
  stored = paste0("sk-", "or-v1-FAKEstoredKey0123456789")
  secret_register(stored, "auth:openrouter", "auth.json")
  h = code_for_history(paste0("k = '", stored, "'"))
  flag = "# gptr: block needs secrets that are not recorded"
  expect_identical(as.character(h), paste0(flag, "\nk = '[secret:auth:openrouter]'"))
  expect_identical(attr(h, "needs"), character())
})

test_that("recorded code preserves needs metadata on repeated passes", {
  vault_reset()
  withr::defer(vault_reset())
  secret_register(fake_ghp, "GITHUB_PAT", "environment")
  first = code_for_history(paste0("token = '", fake_ghp, "'"))
  expect_identical(code_for_history(first), first)
  second = code_for_history(structure(c(as.character(first), "value = 1"), needs = "GITHUB_PAT"))
  expect_identical(attr(second, "needs"), "GITHUB_PAT")
  expect_silent(parse(text = second))
})

test_that("recorded code rejects missing code and invalid needs metadata", {
  for (code in list(NA_character_, c("value = 1", NA_character_))) {
    expect_error(code_for_history(code), class = "gptr_error_invalid_argument")
  }
  for (needs in list(1, NA_character_, "", "auth:openrouter", "TOKEN\n")) {
    code = structure("value = 1", needs = needs)
    expect_error(code_for_history(code), class = "gptr_error_invalid_argument")
  }
})

test_that("unsafe replay-variable metadata remains a flagged marker", {
  vault_reset()
  withr::defer(vault_reset())
  name = paste0("FAKE_", "TOKEN_NAME")
  secret_register(name, name, "environment")
  h = code_for_history(paste0("token = '", name, "'"))
  want = paste0("# gptr: block needs secrets that are not recorded\ntoken = '[secret:", name, "]'")
  expect_identical(as.character(h), want)
  expect_identical(attr(h, "needs"), character())
  expect_identical(code_for_history(h), h)
  expect_silent(parse(text = h))
})


session_lines = function(secret) {
  c(
    paste0("{\"type\":\"session\",\"version\":3,\"id\":\"s0123456789\",",
           "\"timestamp\":\"2026-09-30T10:00:00.000Z\"}"),
    paste0("{\"type\":\"message\",\"id\":\"a1b2c3d4\",\"parentId\":null,",
           "\"timestamp\":\"2026-09-30T10:00:01.000Z\",\"message\":{\"role\":\"user\",",
           "\"content\":[{\"type\":\"text\",\"text\":\"saw ", secret, "\"}]}}"),
    paste0("{\"type\":\"custom\",\"id\":\"e5f6a7b8\",\"parentId\":\"a1b2c3d4\",",
           "\"timestamp\":\"2026-09-30T10:00:02.000Z\",\"customType\":\"gptr.doc_block\",",
           "\"data\":{\"doc\":\"analysis.R\",\"block\":\"7f3a21\"}}")
  )
}

test_that("gptr_scrub() finds a value registered after it was written and rewrites it", {
  vault_reset()
  withr::defer(vault_reset())
  d = withr::local_tempdir()
  dir.create(file.path(d, "sessions"))
  late = paste0("FAKE_late_key_", "0123456789abcdef")
  writeLines(session_lines(late), file.path(d, "sessions", "s.jsonl"))
  writeLines(c("x = 1", paste("#>", late)), file.path(d, "analysis.R"))
  expect_identical(nrow(gptr_scrub(d)), 0L)
  secret_register(late, "LATE_KEY", "session")
  found = gptr_scrub(d)
  expect_identical(sort(basename(found$file)), c("analysis.R", "s.jsonl"))
  expect_identical(unique(found$secret), "LATE_KEY")
  expect_identical(found$count, c(1L, 1L))
  e = tryCatch(gptr_scrub(d, error = TRUE), error = identity)
  expect_s3_class(e, "gptr_error_secret_found")
  expect_identical(nrow(e$findings), 2L)
  expect_false(grepl(late, conditionMessage(e), fixed = TRUE))
  res = withVisible(gptr_scrub(d, dry_run = FALSE))
  expect_false(res$visible)
  expect_identical(nrow(res$value), 2L)
  expect_identical(nrow(gptr_scrub(d)), 0L)
  expect_no_error(gptr_scrub(d, error = TRUE))
  expect_identical(readLines(file.path(d, "analysis.R")), c("x = 1", "#> [secret:LATE_KEY]"))
})

test_that("a rewritten session file stays valid JSONL and gets a gptr.scrub entry", {
  vault_reset()
  withr::defer(vault_reset())
  d = withr::local_tempdir()
  late = paste0("FAKE_late_key_", "0123456789abcdef")
  f = file.path(d, "s.jsonl")
  writeLines(session_lines(late), f)
  secret_register(late, "LATE_KEY", "session")
  gptr_scrub(f, dry_run = FALSE)
  lines = readLines(f, encoding = "UTF-8")
  expect_length(lines, 4L)
  entries = lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  last = entries[[4]]
  expect_identical(last$type, "custom")
  expect_identical(last$customType, "gptr.scrub")
  expect_identical(last$parentId, "e5f6a7b8")
  expect_match(last$id, "^[0-9a-f]{8,12}$")
  expect_identical(unlist(last$data$secrets), "LATE_KEY")
  expect_identical(last$data$count, 1L)
  expect_identical(entries[[2]]$message$content[[1]]$text, "saw [secret:LATE_KEY]")
})

test_that("default paths cover the workspace and the documents bound in its sessions", {
  vault_reset()
  withr::defer(vault_reset())
  late = paste0("FAKE_late_key_", "0123456789abcdef")
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  dir.create(file.path(proj, ".gptr", "sessions"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(proj, ".gptr", "cache", "tmp"), recursive = TRUE, showWarnings = FALSE)
  writeLines(session_lines(late), file.path(proj, ".gptr", "sessions", "s.jsonl"))
  writeLines(late, file.path(proj, ".gptr", "cache", "tmp", "gptr-output-o1a2b3.txt"))
  writeLines(paste("#>", late), file.path(proj, "analysis.R"))
  writeLines(late, file.path(proj, "unrelated.txt"))
  secret_register(late, "LATE_KEY", "session")
  found = gptr_scrub()
  expect_setequal(basename(found$file), c("s.jsonl", "gptr-output-o1a2b3.txt", "analysis.R"))
})

test_that("binary files are reported but never rewritten; bad paths are refused", {
  vault_reset()
  withr::defer(vault_reset())
  d = withr::local_tempdir()
  late = paste0("FAKE_late_key_", "0123456789abcdef")
  bin = file.path(d, "blob.bin")
  writeBin(c(as.raw(0L), charToRaw(late), as.raw(0L)), bin)
  secret_register(late, "LATE_KEY", "session")
  expect_identical(gptr_scrub(d)$count, 1L)
  local_gptr_options(quiet = FALSE)
  expect_message(gptr_scrub(d, dry_run = FALSE), class = "gptr_message_notice")
  expect_identical(gptr_scrub(d)$count, 1L)
  expect_error(gptr_scrub(file.path(d, "missing")), class = "gptr_error_invalid_argument")
  expect_error(gptr_scrub(d, dry_run = NA), class = "gptr_error_invalid_argument")
})

test_that("a long secret is counted and removed through the fixed-string path", {
  vault_reset()
  withr::defer(vault_reset())
  d = withr::local_tempdir()
  huge = paste0(strrep("FAKEhuge", 5000), "end")
  writeLines(c("a", huge, "b"), file.path(d, "log.txt"))
  secret_register(huge, "HUGE_TOKEN", "test")
  expect_identical(gptr_scrub(d)$count, 1L)
  gptr_scrub(d, dry_run = FALSE)
  expect_identical(readLines(file.path(d, "log.txt")), c("a", "[secret:HUGE_TOKEN]", "b"))
})

test_that("the documented example runs on a clean directory", {
  d = tempfile("proj")
  dir.create(d)
  withr::defer(unlink(d, recursive = TRUE))
  writeLines("nothing secret here", file.path(d, "notes.txt"))
  out = gptr_scrub(d)
  expect_identical(names(out), c("file", "secret", "count"))
  expect_identical(nrow(out), 0L)
})

test_that("scrub derives authority only from exact safe document records", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  dir.create(file.path(proj, ".gptr", "sessions"), showWarnings = FALSE)
  late = "FAKE_scrub_authority_0123456789"
  secret_register(late, "LATE_KEY", "test")
  targets = c("allowed.R", "substring.R", "partial.R", ".Rprofile", ".env")
  for (p in targets) writeLines(late, file.path(proj, p))
  outside = withr::local_tempfile(fileext = ".R")
  writeLines(late, outside)
  record = function(doc) {
    list(type = "custom", customType = "gptr.doc_block", data = list(doc = doc))
  }
  records = list(record("allowed.R"), record(".Rprofile"), record(".env"),
                 record(outside), record("../outside.R"),
                 list(type = "message", text = "gptr.doc_block",
                      data = list(doc = "substring.R")),
                 list(type = "custom", customType = "gptr.doc_block",
                      data = list(document = "partial.R")))
  writeLines(vapply(records, json_encode, ""), file.path(proj, ".gptr", "sessions", "s.jsonl"))
  expect_identical(basename(gptr_scrub()$file), "allowed.R")
  expect_identical(nrow(gptr_scrub(c(outside, file.path(proj, ".env")))), 2L)
})

test_that("scrub directory traversal never follows escaping symlinks", {
  skip_on_os("windows")
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  cache = file.path(proj, ".gptr", "cache")
  dir.create(cache, showWarnings = FALSE)
  outside = withr::local_tempdir()
  late = "FAKE_scrub_symlink_0123456789"
  target = file.path(outside, "outside.txt")
  writeLines(late, target)
  expect_true(file.symlink(outside, file.path(cache, "escape")))
  expect_true(file.symlink(target, file.path(cache, "escaped.txt")))
  secret_register(late, "LATE_KEY", "test")
  expect_identical(nrow(gptr_scrub()), 0L)
  expect_identical(nrow(gptr_scrub(cache)), 0L)
  expect_identical(nrow(gptr_scrub(target)), 1L)
})

test_that("scrub audit metadata and known markers remain idempotent", {
  vault_reset()
  withr::defer(vault_reset())
  name = "FAKE_SCRUB_TOKEN_NAME"
  secret_register(name, name, "test")
  f = withr::local_tempfile(fileext = ".jsonl")
  writeLines(session_lines(name), f)
  gptr_scrub(f, dry_run = FALSE)
  once = readBin(f, "raw", file.size(f))
  expect_identical(nrow(gptr_scrub(f)), 0L)
  gptr_scrub(f, dry_run = FALSE)
  expect_identical(readBin(f, "raw", file.size(f)), once)
  last = json_decode(tail(readLines(f, encoding = "UTF-8"), 1L))
  expect_identical(unlist(last$data$secrets), paste0("[secret:", name, "]"))
  # Arbitrary fields with the audit's name remain ordinary data.
  writeLines(json_encode(list(data = list(secrets = name))), f)
  expect_identical(gptr_scrub(f)$count, 1L)
})

test_that("scrub entry IDs account for JSON whitespace and exact metadata", {
  vault_reset()
  withr::defer(vault_reset())
  f = withr::local_tempfile(fileext = ".jsonl")
  late = "FAKE_scrub_id_0123456789"
  secret_register(late, "LATE_KEY", "test")
  writeLines(gsub('"id":', '"id" : ', session_lines(late), fixed = TRUE), f)
  draws = 0L
  testthat::local_mocked_bindings(id_new = function(prefix = "", n = 8L) {
    draws <<- draws + 1L
    c("a1b2c3d4", "e5f6a7b8", "feed1234")[draws]
  })
  gptr_scrub(f, dry_run = FALSE)
  last = json_decode(tail(readLines(f, encoding = "UTF-8"), 1L))
  expect_identical(last$parentId, "e5f6a7b8")
  expect_identical(last$id, "feed1234")
  expect_identical(draws, 3L)
})

test_that("scrub holds session and document writer locks throughout replacement", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  late = "FAKE_scrub_lock_0123456789"
  secret_register(late, "LATE_KEY", "test")
  f = file.path(proj, "session.jsonl")
  writeLines(session_lines(late), f)
  doc_lock = file.path(workspace_root(), "locks", cli::hash_sha1(path_key(f)))
  atomic = write_atomic
  testthat::local_mocked_bindings(write_atomic = function(path, content) {
    if (identical(path, normalizePath(f))) {
      expect_true(dir.exists(paste0(f, ".lock")))
      expect_true(dir.exists(doc_lock))
      holder = readLines(file.path(paste0(f, ".lock"), "pid"), encoding = "UTF-8")
      expect_length(holder, 2L)
      expect_identical(as.integer(holder[1]), Sys.getpid())
      expect_false(dir.create(doc_lock, showWarnings = FALSE))
    }
    atomic(path, content)
  })
  gptr_scrub(f, dry_run = FALSE)
  expect_false(dir.exists(paste0(f, ".lock")))
  expect_false(dir.exists(doc_lock))
})

test_that("scrub refuses held document locks and preserves invalid UTF-8 bytes", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  late = "FAKE_scrub_lock_0123456789"
  secret_register(late, "LATE_KEY", "test")
  f = file.path(proj, "analysis.R")
  writeLines(late, f)
  lock = file.path(workspace_root(), "locks", cli::hash_sha1(path_key(f)))
  dir.create(lock, recursive = TRUE)
  writeLines(paste(Sys.getpid(), as.numeric(ps::ps_create_time(ps::ps_handle()))),
             file.path(lock, "pid"))
  before = readBin(f, "raw", file.size(f))
  suppressMessages(gptr_scrub(f, dry_run = FALSE))
  expect_identical(readBin(f, "raw", file.size(f)), before)
  unlink(lock, recursive = TRUE)
  bytes = c(as.raw(255), charToRaw(late))
  writeBin(bytes, f)
  expect_identical(gptr_scrub(f)$count, 1L)
  suppressMessages(gptr_scrub(f, dry_run = FALSE))
  expect_identical(readBin(f, "raw", file.size(f)), bytes)
})

test_that("scrub preserves old and incomplete session locks instead of stealing them", {
  vault_reset()
  withr::defer(vault_reset())
  f = withr::local_tempfile(fileext = ".jsonl")
  late = "FAKE_scrub_session_lock_0123456789"
  secret_register(late, "LATE_KEY", "test")
  writeLines(session_lines(late), f)
  lock = paste0(f, ".lock")
  dir.create(lock)
  withr::defer(unlink(lock, recursive = TRUE))
  before = readBin(f, "raw", file.size(f))
  for (age in c(60, 25 * 3600)) {
    writeLines(c(as.character(Sys.getpid()),
                 format(as.numeric(ps::ps_create_time(ps::ps_handle())), digits = 17)),
               file.path(lock, "pid"))
    Sys.setFileTime(file.path(lock, "pid"), Sys.time() - age)
    suppressMessages(gptr_scrub(f, dry_run = FALSE))
    expect_identical(readBin(f, "raw", file.size(f)), before)
    expect_true(dir.exists(lock))
  }
  unlink(file.path(lock, "pid"))
  suppressMessages(gptr_scrub(f, dry_run = FALSE))
  expect_identical(readBin(f, "raw", file.size(f)), before)
  expect_true(dir.exists(lock))
})

test_that("scrub rereads after acquiring locks and releases locks after write errors", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  f = file.path(proj, "notes.txt")
  late = "FAKE_scrub_fresh_read_0123456789"
  secret_register(late, "LATE_KEY", "test")
  writeLines(late, f)
  acquire = scrub_lock
  testthat::local_mocked_bindings(scrub_lock = function(path) {
    writeLines(c(late, "concurrent addition"), path)
    acquire(path)
  })
  gptr_scrub(f, dry_run = FALSE)
  expect_identical(readLines(f, encoding = "UTF-8"),
                   c("[secret:LATE_KEY]", "concurrent addition"))
  writeLines(late, f)
  atomic = write_atomic
  testthat::local_mocked_bindings(write_atomic = function(path, content) {
    if (identical(path, normalizePath(f))) stop("synthetic write failure")
    atomic(path, content)
  })
  expect_error(gptr_scrub(f, dry_run = FALSE), "synthetic write failure")
  expect_false(dir.exists(paste0(f, ".lock")))
  expect_false(dir.exists(file.path(workspace_root(), "locks", cli::hash_sha1(path_key(f)))))
})

test_that("scrub refuses symlinked writer-lock roots without writing outside the workspace", {
  skip_on_os("windows")
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  outside = withr::local_tempdir()
  f = file.path(proj, "notes.txt")
  late = "FAKE_scrub_lock_escape_0123456789"
  secret_register(late, "LATE_KEY", "test")
  writeLines(late, f)
  lock_root = file.path(workspace_root(), "locks")
  expect_true(file.symlink(outside, lock_root))
  atomic = write_atomic
  testthat::local_mocked_bindings(write_atomic = function(path, content) {
    expect_false(path_inside(path, outside))
    atomic(path, content)
  })
  suppressMessages(gptr_scrub(f, dry_run = FALSE))
  expect_identical(readLines(f, encoding = "UTF-8"), late)
  expect_length(list.files(outside, all.files = TRUE, no.. = TRUE), 0L)
  expect_false(dir.exists(paste0(f, ".lock")))
})

test_that("dangling cache links do not prevent the scrub audit", {
  skip_on_os("windows")
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  cache = file.path(proj, ".gptr", "cache")
  dir.create(cache, showWarnings = FALSE)
  expect_true(file.symlink(file.path(cache, "missing"), file.path(cache, "dangling")))
  late = "FAKE_scrub_dangling_0123456789"
  secret_register(late, "LATE_KEY", "test")
  writeLines(late, file.path(cache, "output.txt"))
  expect_identical(basename(gptr_scrub()$file), "output.txt")
})

test_that("scrub discovery does not turn lock metadata into rewrite targets", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project()
  withr::local_envvar(GPTR_PROJECT_ROOT = proj)
  sessions = file.path(proj, ".gptr", "sessions")
  dir.create(sessions, showWarnings = FALSE)
  lock = file.path(sessions, "active.jsonl.lock")
  dir.create(lock)
  late = "FAKE_scrub_lock_metadata_0123456789"
  secret_register(late, "LATE_KEY", "test")
  pid = file.path(lock, "pid")
  writeLines(late, pid)
  rec = list(type = "custom", customType = "gptr.doc_block",
             data = list(doc = ".gptr/sessions/active.jsonl.lock/pid"))
  writeLines(json_encode(rec), file.path(sessions, "doc.jsonl"))
  expect_identical(nrow(gptr_scrub()), 0L)
  expect_identical(nrow(gptr_scrub(pid)), 1L)
})
