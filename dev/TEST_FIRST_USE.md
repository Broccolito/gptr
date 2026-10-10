# Test first-use provider setup

The first-use picker runs only for a new interactive `peter()` console without an explicit or
effective configured model. It offers Codex CLI, Claude Code CLI and manual API/Ollama setup.
It does not install tools, sign in, send a model request or grant context-sharing consent.

## Prepare an isolated manual test

Prefer a disposable R user configuration directory for development tests. If you deliberately
want to reset your normal gptr settings, close active gptr/R sessions before applying or restoring
this helper, and start a fresh R process afterward. The helper moves the entire `settings.json`
file, including its model, permissions and acknowledgment settings; CLI sign-in storage is separate.
It never deletes the backup or resets CLI credentials.

From the repository root, preview the path without changing any files:

```sh
Rscript --vanilla dev/reset-user-settings.R
```

Only when you intend to test with your normal user settings, move them to a unique backup:

```sh
Rscript --vanilla dev/reset-user-settings.R --apply
```

Keep the printed full backup path. The helper bypasses gptr's active settings cache, which is
why active sessions must be closed first. Start a fresh interactive R session with no `gptr.model`
option or session-level model override, then run:

```r
devtools::load_all()
peter()
```

Install and sign in to any CLI you want to test beforehand, following that CLI's own instructions.
Do not paste credentials into the console, the guide or a recorded transcript.

## Expected picker behavior

- **Signed in**: an available expected CLI adapter saves `codex/default` or
  `claude-cli/default` at user scope and opens the console. Enter `/exit` without sending a
  prompt when you only want to check setup. On the next opening, the configured default skips
  the picker.
- **Not signed in**: choosing that CLI returns to R with `codex login` or `claude auth login`
  instructions and saves no model. gptr does not run those sign-in commands.
- **Unknown**: older/unsupported CLI status commands and failed checks report unknown. An
  explicit choice of an available CLI is accepted with a notice; unknown does not mean signed out.
- **Unavailable or overridden**: a missing CLI or a same-name provider using a different adapter
  returns to R without choosing a fallback or saving a default.
- **Manual setup or cancellation**: returns to R without saving. Manual setup prints API and
  local Ollama commands; it does not execute them.

`gptr_providers(check_login = TRUE)` independently checks local CLI-reported login status.
It sends no model request and does not validate credentials online. A Codex API-key login can
also count as signed in, so this report does not establish subscription billing. Inspect the
CLI's active account and billing before making a live call. Context-sharing acknowledgment and
tool permissions remain separate from choosing a default.

Existing sessions, explicit or effective configured models, `.stdin = TRUE` and noninteractive
workflows skip the picker. Calls with a prompt use normal model resolution. User-scope defaults
apply across sessions and projects unless a higher-priority setting overrides them.

## Configure the manual path

For an API provider, use masked key entry or an existing environment file:

```r
gptr_login("openai", method = "key")
# Alternatively: gptr_env("~/keys/.env")
gptr_config(model = "openai/gpt-6-sol", .scope = "user")
peter()
```

For Ollama, start your own local server and use an already installed conversational model.
Discovery contacts that server but never pulls or installs a model:

```r
gptr_models(provider = "ollama", refresh = TRUE)
# Replace <installed-model> with a local chat model from the listing.
gptr_config(model = "ollama/<installed-model>", .scope = "user")
peter()
```

See the [language-model guide](../vignettes/language-models.Rmd.orig) for model capabilities and
local-only checks, and the [console guide](../vignettes/interactive-console.Rmd.orig) for input.
Do not infer live inference success from the setup menu or cached provider listing alone.

## Restore normal settings

Close the test's R session. Use the exact full backup path printed by `--apply`:

```sh
Rscript --vanilla dev/reset-user-settings.R --restore "/full/path/settings.json.setup-backup-..."
```

If testing created a new `settings.json`, restoration first backs it up under a different name,
then moves the original settings back. Start a fresh R session after restoration. The helper
only moves `settings.json`; nearby files and CLI sign-in state are untouched.
