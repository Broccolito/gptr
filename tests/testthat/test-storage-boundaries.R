# Disposable storage ownership regressions; no real project or credential content.

test_that("cache info and cleanup stay inside owned cache directories", {
  for (kind in c("s1", "s2", "tmp")) for (action in c("clear", "prune")) {
    for (placement in c("nested", "root")) local({
      project = local_project()
      outside = withr::local_tempdir("gptr-foreign-cache-")
      foreign = file.path(outside, "victim.json")
      writeLines('{"doc":"missing.R","block":"gone00"}', foreign)
      Sys.setFileTime(foreign, Sys.time() - 100 * 86400)
      before = readBin(foreign, "raw", file.size(foreign))
      dir = file.path(project, ".gptr", "cache", kind)
      owned = NULL
      if (placement == "nested") {
        owned = if (kind == "tmp") file.path(dir, "owned.json") else
          file.path(dir, "bb", "owned.json")
        dir.create(dirname(owned), recursive = TRUE, showWarnings = FALSE)
        writeLines('{"doc":"missing.R","block":"gone00"}', owned)
        Sys.setFileTime(owned, Sys.time() - 100 * 86400)
        if (kind == "tmp") local_symlink(foreign, file.path(dir, "linked.json")) else
          local_symlink(outside, file.path(dir, "aa"))
      } else {
        if (dir.exists(dir)) unlink(dir, recursive = TRUE)
        local_symlink(outside, dir)
      }
      label = paste(kind, action, placement)
      info = gptr_cache("info", kind)
      n = if (is.null(owned)) 0L else 1L
      expect_identical(info$entries[info$kind == kind], n, label = label)
      expect_identical(gptr_cache(action, kind), n, label = label)
      expect_true(file.exists(foreign), label = label)
      if (file.exists(foreign)) {
        expect_identical(readBin(foreign, "raw", file.size(foreign)), before, label = label)
      }
      if (!is.null(owned)) expect_false(file.exists(owned), label = label)
    })
  }
})

test_that("a cache-kind link to owned workspace storage still works", {
  project = local_project()
  owned = file.path(project, ".gptr", "owned-s1")
  dir.create(owned)
  file = file.path(owned, "answer.json")
  writeLines("{}", file)
  local_symlink(owned, file.path(project, ".gptr", "cache", "s1"))
  expect_identical(gptr_cache("info", "s1")$entries[1L], 1L)
  expect_identical(gptr_cache("clear", "s1"), 1L)
  expect_false(file.exists(file))
})

test_that("checkpoint GC never removes foreign content through storage links", {
  for (placement in c("nested", "store", "blobs", "objects")) local({
    project = local_project()
    root = file.path(project, ".gptr")
    store = file.path(root, "checkpoints")
    outside = withr::local_tempdir("gptr-foreign-checkpoint-")
    old = Sys.time() - 40 * 86400
    rel = switch(placement, store = "blobs/ab/foreign.gz", objects = "s9999999999/data.txt",
                 "foreign.gz")
    foreign = file.path(outside, rel)
    dir.create(dirname(foreign), recursive = TRUE, showWarnings = FALSE)
    writeLines("outside sentinel", foreign)
    Sys.setFileTime(c(foreign, dirname(foreign)), old)
    before = readBin(foreign, "raw", file.size(foreign))
    if (placement != "store") dir.create(store)
    owned = NULL
    if (placement == "nested") {
      dir.create(file.path(store, "blobs"))
      owned = file.path(store, "blobs", paste0(strrep("cd", 16L), ".gz"))
      writeLines("owned old blob", owned)
      Sys.setFileTime(owned, old)
      local_symlink(outside, file.path(store, "blobs", "ab"))
    } else {
      link = switch(placement, store = store, blobs = file.path(store, "blobs"),
                    objects = file.path(store, "objects"))
      local_symlink(outside, link)
    }
    n = if (is.null(owned)) 0L else 1L
    expect_identical(ckpt_gc(root, days = 30)$deleted, n, label = placement)
    expect_true(file.exists(foreign), label = placement)
    if (file.exists(foreign)) {
      expect_identical(readBin(foreign, "raw", file.size(foreign)), before, label = placement)
    }
    expect_false(file.exists(file.path(outside, "index.json")), label = placement)
    if (!is.null(owned)) expect_false(file.exists(owned), label = placement)
  })
})

test_that("checkpoint GC permits a blob directory linked inside its owned store", {
  project = local_project()
  root = file.path(project, ".gptr")
  store = file.path(root, "checkpoints")
  owned = file.path(store, "owned-blobs")
  dir.create(owned, recursive = TRUE)
  file = file.path(owned, paste0(strrep("cd", 16L), ".gz"))
  writeLines("owned old blob", file)
  Sys.setFileTime(file, Sys.time() - 40 * 86400)
  local_symlink(owned, file.path(store, "blobs"))
  expect_identical(ckpt_gc(root, days = 30)$deleted, 1L)
  expect_false(file.exists(file))
})

test_that("discovered project instructions cannot read escaped or guarded link targets", {
  files = c("AGENTS.override.md", "AGENTS.md", "CLAUDE.md", "CLAUDE.local.md",
            ".gptr/vignette.Rmd")
  for (rel in files) for (target in c("outside", "guarded")) local({
    project = p07_project(stats::setNames(list("owned instruction"), rel))
    outside = withr::local_tempdir("gptr-foreign-instructions-")
    foreign = if (target == "outside") file.path(outside, "sentinel.txt") else
      file.path(project, ".env")
    writeLines("PRIVATE_SYNTHETIC_STORAGE_SENTINEL", foreign)
    s = p07_session("manual")
    first = context_first_message(s, list(turn = 1L, human = FALSE))
    expect_true(any(grepl("owned instruction", vapply(first, function(b) b$text, ""),
                          fixed = TRUE)))
    session_append(s, list(type = "message", message = msg_user(first)))
    path = file.path(project, rel)
    unlink(path)
    local_symlink(foreign, path)
    fresh = context_first_message(s, list(turn = 1L, human = FALSE))
    update = context_block_by_name(s, "project_instructions_update",
                                   list(turn = 2L, human = FALSE))
    texts = vapply(c(fresh, update), function(b) b$text, "")
    expect_false(any(grepl("PRIVATE_SYNTHETIC_STORAGE_SENTINEL", texts, fixed = TRUE)),
                 label = paste(rel, target))
    plan = context_instruction_items(list(mode = "plan", human = FALSE))
    expect_false(any(grepl("PRIVATE_SYNTHETIC_STORAGE_SENTINEL",
                          vapply(plan, function(b) b$text, ""), fixed = TRUE)))
  })
})

test_that("safe project instruction links and user-level instructions are retained", {
  project = p07_project(list("rules.md" = "safe linked project instruction"))
  user = file.path(gptr_user_dir("config", create = TRUE), "AGENTS.md")
  writeLines("user-level instruction", user)
  withr::defer(unlink(user))
  local_symlink(file.path(project, "rules.md"), file.path(project, "AGENTS.md"))
  s = p07_session("manual")
  first = context_first_message(s, list(turn = 1L, human = FALSE))
  texts = vapply(first, function(b) b$text, "")
  expect_true(any(grepl("safe linked project instruction", texts, fixed = TRUE)))
  expect_true(any(grepl("user-level instruction", texts, fixed = TRUE)))
})
