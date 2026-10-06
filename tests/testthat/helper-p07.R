# Shared helpers of the P07 prompt tests.

# A session on a fake provider that answers "ok"
p07_session = function(mode = "auto", preset = NULL, .env = parent.frame()) {
  local_fake_provider(list("ok"), .env = .env)
  session_new("fake/fake-1", mode, home = new.env(), preset = preset)
}

# A temporary project that project_root() resolves to; returns its path
p07_project = function(files, .env = parent.frame()) {
  local_project(files = files, .env = .env)
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd(), .local_envir = .env)
  getwd()
}

block_kinds = function(blocks) vapply(blocks, function(b) b$kind %||% b$type, "")

wrap = function(name, x) paste0("<", name, ">\n", x, "\n</", name, ">")

# The stand-ins of fixtures/bench/standins.R (shared with dev/bench/tokens/run.R), bound by name:
# the lint's object_usage_linter cannot see names that source() defines.
standins_env = local({
  source(test_path("fixtures", "bench", "standins.R"), local = TRUE)
  environment()
})
prefix_fixture = standins_env$prefix_fixture
prompt_standins_register = standins_env$prompt_standins_register

# Compose one case of prefix-baseline.json with the stand-ins for other owners' texts
compose_case = function(name, .env = parent.frame()) {
  pb = prefix_fixture()
  cs = pb$cases[[name]]
  s = p07_session(cs$mode, cs$preset, .env = .env)
  prompt_standins_register(pb$standins, session_data(s)$id, sections = unlist(cs$sections),
                           exclusive = TRUE)
  doc = if (isTRUE(cs$document)) list(path = file.path(project_root(), "analysis.R"), format = "R")
  prompt_compose(s, list(interactive = cs$human, doc = doc))
}
