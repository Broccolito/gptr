# Recursive peter: `gptr_coach()` and in-memory harnesses

Status: accepted and implemented in P29 (dev/plan/P29-gptr-coach.md), 2026-10-28.
Sources: Harness² (Xu et al. 2026, arXiv 2610.14224; github.com/google-research/harness2 at
`1cfe254`) and gptr at `13a917ff`. Every gptr name cited below was checked against that commit;
names marked **NEW** do not exist yet. Twelve research reviews and nine critical reviews shaped
this revision.

**Revision 2 (maintainer requests, 2026-10-27):** `gptr_coach()` takes a starting harness and
returns a harness held in memory, called like `peter()`. Harness²'s loop settings are arguments.
Any model may coach. There is no budget argument and no library. Every session runs in its own R
process.

**Revision 3 (maintainer questions, 2026-10-27):**
- A coached harness can carry hard rules as data: `never` refuses an action, and `require` names
  an action that must happen before finishing. gptr's own code enforces both (1.8, 3.2).
- Harness calls and `gptr_coach()` calls are recorded in scripts and documents, like `peter()`
  calls, and they replay without a model (1.10, 3.6).
- Results come back from a run as plain JSON text, not as an `.rds` file. That works on every R
  version gptr supports, so there is no R 4.4 requirement (3.3).
- The model rule is stated precisely: it is about how gptr reaches a model, not which model it is
  (1.5).
- `check` stays (1.7).

**Revision 4 (maintainer request, 2026-10-28):**
- People whose only access to a strong model is a Claude Code or Codex subscription can coach.
  Both routes are allowed for runs, coaches and the judge, under checks on every session (1.5,
  3.7).
- Section 1.1 explains the two functions, `gptr_tailor()` and `gptr_coach()`, side by side.

---

## Part 1. The idea in plain words

### 1.1 A harness is a function

A language model on its own only writes text. `peter()` turns it into an agent by surrounding it
with instructions, tools, skills, permission checks, budgets and undo. Harness² calls that
surrounding layer the **harness**. It found that re-running a task with a harness tuned on an
earlier attempt at that task scored higher on three professional benchmarks: up to 11.5, 4.5 and
11.8 points. The model doing the task stayed the same. A stronger model did the tuning, and a
shared library of earlier tunings supplied about 2 to 3 of those points.

In gptr a harness is **a function you call like `peter()`**. Apart from `peter` itself, every
harness is an object of one kind, class `gptr_harness`, wherever it comes from:

| Where it comes from | How | Does making it use a model? |
|---|---|---|
| gptr itself | `peter` | no |
| your own fixed choices | `auto_peter = gptr_tailor(peter, mode = "auto", extensions = my_hooks)` | no |
| coaching | `survey_peter = gptr_coach("Clean this survey", survey, harness = auto_peter)` | yes |
| someone else | `their_peter = gptr_tailor(readRDS("their_peter.rds"))` | no |

**The two functions.** Both return a harness. They differ in how they decide what goes into it.

| | `gptr_tailor()` | `gptr_coach()` |
|---|---|---|
| What it does | builds a harness from parts **you** give it | finds better *coaching* (the note, skills, review and rules that peter is given; 1.2) by **running your task** and comparing runs |
| Uses a model? | no; it runs nothing and returns at once | yes; it runs several sessions, takes minutes and uses tokens |
| Starts from | `x`: `peter` or a harness | `harness =`: `peter` or a harness |
| Other input | `...`: `peter()` arguments to fix (`mode`, `model`, `tools`, `extensions`, ...), merged over the starting harness's; `rules =`: your own hard rules; `coaching =`: coaching written by hand; `dir =`: a folder to write files to | `...`: the task (your prompt and objects), plus any `peter()` arguments for this call only; `budget` also caps each coach session, and none of these are kept; `check =`: your test of a good result; `coach =`, `k =`, `strategy =`, `focus =`, `surface =`: how to coach |
| Returns | a new harness: your starting harness with the parts you gave, a new id and an empty record | a new harness: your starting harness plus the improved coaching, or, if nothing was kept, your starting harness with only its record replaced. The record says what happened |
| Can change | your part (fixed arguments, your rules) and, by hand, the coaching | only the coaching |

How they are related:
- **One kind of object.** Both return a harness (class `gptr_harness`): a function you call like
  `peter()`. Each accepts the other's result as its starting point.
- **`gptr_coach()` uses `gptr_tailor()`.** When `gptr_coach()` finishes, its result is
  `gptr_tailor(<starting harness>, coaching = <the improved coaching>)`, with this call's record
  attached. A recorded script shows exactly that line (1.10).
- **Different halves.** `gptr_tailor()` is how *you* change a harness. `gptr_coach()` is how a
  *coach* changes it, and a coach may touch only the coaching (1.2).
- **Typical order.** Make an altered peter with `gptr_tailor()`, coach it with `gptr_coach()`,
  use the result, coach it again on the next task, and adjust it by hand with `gptr_tailor()`
  whenever you like.

`gptr_coach()` accepts any harness as its starting point, including one made by an earlier
`gptr_coach()` call or one you received from someone else. That is the recursion. What it refuses is an
arbitrary R function: to change peter by hand, use `gptr_tailor()`.

### 1.2 Two halves

1. **Your part, never changed by a coach.** This is `peter` itself, with every tool, permission
   check, secret guard, budget and undo. It also includes what you fix when you make a harness:
   - arguments such as `mode`, `model`, `tools` or `.opts`;
   - your own hooks and policies, as `extensions`;
   - your plugins, skills and prompt sections;
   - your own hard rules (1.8).

   A coach never sees your R code and never edits it.
2. **The coaching, which coaches may change.** It is data in four parts, and gptr's own code
   carries out each one:
   - **note**: a short note added to peter's instructions on every call. It holds how to approach
     this kind of task, general facts about it, and tips on using the tools.
   - **skills**: how-to guides that peter opens when it needs them. Any R code in a skill is an
     example. When peter runs it, every line goes through its usual checks.
   - **review**: a second look before finishing. When peter is about to stop, gptr hands it the
     review text once or twice ("open the output again and compare it with the task: ...").
   - **rules**: hard rules. A `never` rule refuses an action. A `require` rule names an action that
     must happen before peter finishes.

Empty coaching leaves the harness you started from. In this document, *the coaching* always means
this data; one call of `gptr_coach()` is *a coaching call*.

### 1.3 What you type

```r
auto_peter = gptr_tailor(peter, mode = "auto")              # an altered peter, made by hand
survey_peter = gptr_coach("Clean this survey and fit the outcome model", survey,
                           harness = auto_peter, check = function(r) is.data.frame(r$value))
survey_peter                                                 # what was tried, what changed, why
survey_peter("Clean this year's survey", survey_2026)        # use it exactly like peter()
better = gptr_coach("Clean this survey and weight by region", survey_2026, harness = survey_peter)
saveRDS(better, "survey_peter.rds")                          # share it
gptr_tailor(better, dir = "survey_peter/")                  # write it out as files to read
```

Arguments you give in `...`, such as `mode = "auto"` or `budget =`, apply to that call's runs
only. To keep one in the harness, put it in the starting harness, as `auto_peter` does above.

Nothing is written to disk unless you save it, export it, or record it in a script (1.10).

### 1.4 What happens, with the default settings

1. **Try.** Your starting harness does the task once.
2. **Propose.** Two coaches read the full transcript of that run. Coach A improves *how peter
   works*: steps, tools, checking its output, finishing, and hard rules. Coach B adds *what an
   expert in the subject knows*. Neither sees the other's work. Coaches get no tool that can read
   files or act: they only write data.
3. **Probe.** Each coach's version does the task once.
4. **Compose.** A third coach, the *composer*, compares the runs side by side and keeps the
   changes that visibly helped. Keeping your starting harness unchanged is an allowed answer.
5. **Final try.** The composed version does the task once more. Code then decides whether to keep
   it (1.6).

**Where it runs.** Each of those seven sessions runs in its own fresh R process, never in your
session. Sessions that do not depend on each other run at the same time: first the two coaches,
then the two probes. Each run gets:
- an empty folder of its own as its working folder;
- copies of the objects you passed in `...`;
- your own permission rules, hooks and policies.

A run cannot change your objects. gptr refuses its attempts to write outside its folder or to
install packages, by every route gptr recognises. It sends back plain text only (3.3). When it
ends, its folder and process are deleted.

**When nobody is there.** A step that would need a person's approval ends that run as `blocked`.
That is why most tasks need `mode = "auto"`. Effects outside R, such as data sent over the
network, still happen exactly as in `peter(mode = "auto")`.

**Cost.** Four runs of your task plus three shorter coach sessions. gptr prints the count before it
starts. A `budget = ` you pass caps each run and each coach session, as in `peter()`, so a default
call can spend up to seven such budgets. On a Claude Code or Codex plan, the sessions use your
plan's limits instead (1.5).

### 1.5 The settings you can change

| Argument | Meaning | Default |
|---|---|---|
| `harness` | the harness to start from (1.1) | `peter` |
| `k` | how much coaching. With `"parallel"`: k starting runs, k coaches of each focus, and k composers that each see every probe, then a blind judge picks among the finals. With `"sequential"`: k starting runs, then k rounds, each building on the last | `1` |
| `strategy` | `"parallel"` or `"sequential"`. It is not called `mode`, so that `mode = "auto"` still reaches peter | `"parallel"` |
| `focus` | every focus to run, one proposing coach each: `"procedure"` (how peter works), `"domain"` (what an expert knows), or your own words | both |
| `surface` | which coaching parts may change | `c("note", "skills", "review", "rules")` |
| `coach` | the model for coaches, the composer and the judge | the runs' model |
| `check` | your own test of a good result (1.7) | none |

These defaults follow Harness²'s code. Its paper did its tuning with a stronger model and tested
same-model coaching only at `k = 2`, so the default pairing (one model, `k = 1`) is untested. Pass
`k = 2` or a stronger `coach`. gptr says so once when you use the defaults. `review` and `rules`
are gptr's own additions.

Harness²'s fixed rules are kept:
- an invalid coach answer gets one retry, as a follow-up in the same coach session and under the
  same budget, and after that the stage keeps the harness it started from;
- every composed harness gets its final try.

**Count.** Each call runs `k × (2 + focuses)` runs of your task and `k × (1 + focuses)` coach
sessions, plus up to one judge session when `k > 1`. The defaults give 4 and 3.

**Which models.** Coaching works on API keys and on subscription plans. Runs, coaches and the
judge may each use any of these, mixed as you like:

- **An API key or a local server.** gptr calls the model directly and runs every step itself. That
  covers Claude, GPT and Gemini models, OpenRouter, Bedrock and Azure, and local Ollama, LM Studio,
  llama.cpp or vLLM. Example: `coach = "anthropic/claude-opus-5-5"`.
- **A Claude Pro or Max plan, through Claude Code** (`model = "claude_code"`). Many people pay for
  no API key, so this route is fully supported. gptr already switches off all of Claude Code's own
  tools, so the only tools left are gptr's, and gptr checks every call. For coaching, gptr also
  stops the CLI saving the session or using its memory, and it checks every session before trusting
  its answer (3.7).
- **A ChatGPT plan, through Codex** (`model = "codex"`). Codex normally runs its own shell, which
  gptr cannot check, so coaching switches that shell off. A run then acts only through gptr's
  tools, which gptr checks, inside Codex's read-only sandbox. A coach or the judge gets no tool
  that can read or act. gptr checks every session (3.7).

Each route draws on what you pay for. With an API key you pay per token. On a plan, the sessions
use your plan's 5-hour and weekly limits, which your other Claude or ChatGPT use shares. On a plan,
`gptr_coach()` runs at most two sessions at once, and it tells you before it starts how many
sessions it will run. If a plan limit is reached, it stops, keeps your starting harness, and tells
you when the limit resets (3.7).

**Refused**, before anything runs:
- routers, because your own R function chooses the model at each request, so gptr cannot check it
  in advance;
- models used only for quick choices and labels (System 1), which have no agent loop to coach;
- a Claude Code or Codex version older than the oldest one gptr was tested with, or one whose
  checks fail.

A run that switches to a refused model partway through is stopped. These limits apply only inside
`gptr_coach()`. A harness you call yourself accepts every model `peter()` accepts. With Codex in
normal use, its own shell commands bypass the harness's `never` rules, as they bypass all of
gptr's checks.

If you set no model and have no Anthropic, OpenAI or Google key, gptr uses Claude Code when it is
installed, and otherwise Codex. So with only a Claude or ChatGPT plan, `gptr_coach()` needs no
model argument.

### 1.6 What you get back

You always get back a harness:

- **Kept**: the final try ended normally and produced at least the kinds of result your starting
  harness produced (a value, objects, files, or else text). It also:
  - took no riskier kind of action than the starting runs, not counting the actions a `require`
    rule asked for;
  - met every `require` rule;
  - passed your `check`.

  You get your starting harness plus the new coaching. gptr prints the new coaching in full so you
  can read what was added.
- **Not kept**: you get your starting harness unchanged apart from a new record, and gptr says
  why.

The harness carries a short **record**: each run's outcome, turns, tokens, cost, highest risk level
and unmet requirements, and the decision with its reason. The record holds no data from your
runs. `survey_peter$record` shows it. The full **report**, with every run's answer and value, the
transcripts and the coaches' notes, stays in this R session only, as `survey_peter$report`. The
coaching itself may still mention facts from your data, so read it before you share a harness.

*Kept* is not proof that the new harness is better. Nobody has measured it beating the old one on
new data.

### 1.7 What `check` does, and why to keep it

`check` is optional. It is a small R function that **you** write. It looks at a finished run and
answers `TRUE` or `FALSE`:

```r
check = function(r) is.data.frame(r$value) && !anyNA(r$value$outcome)
```

`r` is plain data: `r$text`, `r$status`, `r$value` and `r$objects`.

- gptr calls `check` on each final try. A final that fails it is not kept.
- Coaches, the composer and the judge never see `check` or its result. They are asked to do the
  task better, not to pass your test. Harness² uses no labels at all for the same reason. In the
  Darwin Gödel Machine study, a self-modifying agent learned to fool a check it could see.

**Recommendation: keep it.**
- It is the only place where *you* say what a good result is. Every other test gptr applies is
  generic: the run finished, produced the same kinds of result, met the hard rules, and took no
  riskier kind of action.
- It is written by a person, never by a model.
- It is cheap: it runs once per final, on plain data.
- It cannot be gamed by the coaching, because no coach sees it.

The argument against it is that Harness² got its gains with no labels at all. The answer is that
`check` stays optional. When it is missing, gptr says once that it can judge only whether a run
finished and delivered.

### 1.8 Hard rules, hooks and execution graphs

**Hard rules a coach can add.** A coach writes them as data in gptr's permission-rule language,
and gptr's own code enforces them:

```r
rules = list(
  never   = list(list(rule = "r(category:install)",
                      why  = "Use the installed packages; do not install new ones.")),
  require = list(list(id = "save-results", any = "r(fn:write.csv,saveRDS)",
                      text = "Save the final table with write.csv() or saveRDS() before you finish.")))
```

- **`never`.** gptr refuses every call that matches, in every mode, and tells peter why. When rules
  disagree, any refusal wins, so a coach rule can only forbid, never allow. Examples that work:
  - no package installs;
  - no writes under `data/raw/`;
  - no network calls;
  - no calls to a named function such as `stepAIC`.
- **`require`.** Before peter may finish, gptr checks whether a matching action happened in this
  run. If not, it reminds peter with the text, at most twice. A run that still ends without it is
  reported as unmet, and in a `gptr_coach()` call that means the new coaching is not kept. Examples that
  work:
  - save results with `write.csv()` or `saveRDS()`;
  - call `set.seed()`;
  - run your validation function;
  - read the codebook, as `any = "r(fn:read.csv,readLines)"` with `contains = "codebook"`;
  - produce a plot.

  gptr can remind peter and report an unmet requirement, but it cannot force the model to act.
- **Who writes them.** Only the procedure coach writes rules. Each rule must point to the moment in
  a run where the forbidden action happened, or where the required one was missing. The composer
  may keep or drop probed rules but cannot invent new ones. The judge never writes rules.
- **Limits.** The rule language reads the code peter runs before it runs. A path or function name
  that the code computes at run time can slip past a rule. "Do Y before Z" orderings are not
  expressible in this version.

**Your own hard rules** stay in your half, and no coach can remove them:
- write them in the same language with `gptr_tailor(peter, rules = list(never = ..., require = ...))`;
- or use `gptr_permissions()`;
- or write your own policy or hook as `extensions`.

**What if a rule needs real R code?** A coach never writes code that runs. Code written by a model
would run outside gptr's risk checks, and Harness² checked such code only for syntax. If a coach
finds that a real hook is needed, for example to transform data automatically, it says so in its
notes, which you read in the report. Only you can add code, with
`gptr_tailor(h, extensions = my_new_hook)`. A need that comes up often becomes a new kind of data
rule in gptr.

**Execution graphs and loops.** A coached harness can use them in three ways:
- **Inside a run.** peter can already start sub-agents from its own R code, and run them in
  parallel or as teams (`peter(..., parallel = 4)`, `agents =`). Every such call is risk-checked.
  The note and skills can teach it when to do so.
- **Around a run.** `review` and `require` form a check-then-revise loop: peter looks again with
  its tools before it finishes. Research finds two loops that pay:
  - check-then-revise, when the check uses a real signal such as re-opening the output, not
    reflection alone;
  - best-of-k, where several runs are made and a judge picks one.

  A later phase may add best-of-k if measurement shows a need.
- **Your own flow.** Any R function you write can call your harness at each step. `gptr_coach()`
  coaches the harness that every step uses. It does not rewrite your function.

A coach cannot invent new flows. In the research, systems that let a model write agent code freely
scored below a single plain call. Systems that chose from a few fixed steps did better. In the one
study that measured both, better instructions gave 11 points and a better flow 3. With strong
models, adding agents often stopped helping or made results worse.

### 1.9 What stays the same

`peter()` gets no new argument, option or toggle. A harness acts only in the sessions it starts:
its coaching stays with a session for that session's continuations, and nowhere else. Two fixes in
phase P29a also tighten plain `peter()` calls:
- your keyed extension factories load once per session;
- your own policies now bind every sub-agent that model code starts.

Phase P29e changes two things for every `peter()` call on a plan: a weekly or model-family limit
is no longer retried, and `.opts$returns` works on Claude Code.

### 1.10 Recording: coaching and harness calls in your scripts

gptr already records top-level `peter()` calls into R scripts, R Markdown, Quarto and Jupyter
notebooks. It writes the code the agent ran below the call. Given the same data and packages, a
recorded script replays later with no model and no keys, or reruns with another model. The same
now holds for harnesses:

- **A harness call**, `survey_peter("Clean ...", survey_2026)`, is recorded like a `peter()` call.
  Its block also names the coaching it used, as `harness=survey_peter:<hash>`. If the coaching later
  changes, the block is stale and is regenerated, just as when you edit a prompt.
- **A coaching call**, `survey_peter = gptr_coach(...)`, is recorded as the harness it produced. The
  coaching is written below the call as plain R text, with one line per run and the decision:

  ```r
  survey_peter = gptr_coach("Clean this survey ...", survey, harness = auto_peter)
  # >>> gptr:7f3a1c kind=coach harness=survey_peter:9c41e2d0 start=auto_peter:5b0e77a1 ...
  survey_peter = gptr_tailor(auto_peter, coaching = list(
    note = "Before modelling, list every variable with skip patterns ...",
    skills = list(list(name = "survey-weights", description = "...", text = "..."))))
  ## Run start: ended normally, 14 turns, risk 2
  ## Run final: ended normally, 11 turns, risk 2
  ## Decision: kept (delivered as at start; risk 2 <= 2; check TRUE)
  # <<< gptr:7f3a1c
  ```

  On replay, gptr rebuilds the same harness from that text: no model, no keys, no R processes, no
  seven sessions. `GPTR_REPLAY=replay` still proves that a script makes no model call, coaching
  included.
- **Privacy.** In a script, only the coaching and one line per run are written: the same text gptr
  prints when it keeps new coaching. Your data, transcripts, values and `check` are never written.
  The coaching can still mention facts drawn from your data, so read it before you commit the
  script.

---

## Part 2. How Harness² does it, and where gptr departs

| Idea | Harness² | Evidence |
|---|---|---|
| A harness is a tree of files | an allowlisted *editable surface* of eight components; files outside it are dropped | `core/tree.py:31, 40-110` |
| Edits name only what changes | omitted files are inherited; keeping the base is a valid answer | `core/prompts.py:179-193, 333-335` |
| Two scoped proposals | INV (how the agent works) and DOM (what a practitioner knows), blind to each other | `prompts.py:347-407`; `recursion.py:368-387` |
| Parallel mode | k base runs; k INV and k DOM candidates, each probed once; k composers, each seeing all 2k candidates; each composition run once | `recursion.py:343-449`; `prompts.py:893-894` |
| Sequential mode | k base runs, then k rounds of one INV, one DOM and one composer; every round keeps the same base runs as evidence and sees all earlier rounds | `recursion.py:497-562`; `prompts.py:975-977` |
| Run counts | R = 4k executor runs and P = 3k editor sessions in either mode; retries are counted apart | `ledger.py:15-33` |
| Compose from contrasts | merge, adopt one or keep base; every decision cites a moment in a run; an edit whose run produced nothing is unsafe | `prompts.py:893-961` |
| No score in the loop | grader files are refused from every evidence folder; "delivered" is the only mechanical signal | `context.py:399-491` |
| Selection | for k > 1, a blind selector sees only the finals' deliverables; the base is excluded and the selected final is always adopted | `selection.py:71-153, 360-399` |
| Invalid proposals | one retry with the validator's message, then fall back | `recursion.py:36, 176-251` |
| Hard rules | prose (`guardrails.md`); hooks and plugins written as code, allowed only on "repeated evidence that clear prose is skipped" and never to "block valid completion" | `prompts.py:231, 443-452`; paper Fig 19 |
| Across tasks | a library of adopted harnesses, each with one lesson; every task restarts from the base | `library.py:43-47, 101-181` |

**Measured.**
- One step (k = 1) improved every model–harness pair on all three benchmarks: by up to 11.5 points
  on WorkBuddy-Bench, 4.5 on JobBench and 11.8 on LAB. Raising k to 5 added up to 6.7 more.
- Ablations at k = 1: removing the library cost 3.1 and 1.8 points, removing the INV/DOM scoping
  2.9 and 3.7, and removing composition 1.6 and 1.9.
- Removing skills cost 5.3 points and removing scripts 3.7. No result isolates hooks or plugins,
  and the paper says both are rare in adopted harnesses.
- Editing without any execution evidence *hurt*: WorkBuddy Code fell from 73.4 to 63.2.
- The editor in the headline results was a separate strong model (Claude Opus 4.8). Same-model
  editing helped all five models tested, at k = 2.
- The case study's gain (43.1 to 77.8) needed no sub-agents. It came from an inventory step, a
  domain skill, and a script that re-opened the outputs.

**Deliberate departures.**
1. *Hooks, plugins and scripts are never written by a model; hard rules only as data.* Harness²
   compiles its scripts and never reads plugin code. Dropping scripts cost it 3.7 points; R code in
   a skill, which peter runs through its checks, recovers part of that.
2. *Coaches get no tool that can read or act.* Their evidence is inside their prompt.
3. *No library and no lessons.* A coached harness carries its coaching forward, and you choose
   where to start. Harness²'s library was worth 1.8 to 3.1 points.
4. *Generalise, do not memorise.* Facts about this dataset stay out of the coaching. This follows
   Harness²'s JobBench rule; its two largest headline gains came under the opposite, default rule.
5. *Code decides adoption.* Harness² always adopts the selected final. gptr keeps the new coaching
   only if the final passes `passes()` (3.4).
6. *`review` and `require` are gptr's own.* The closest measured analogue is AHE's finish hook,
   worth 2.2 points on a strong model.
7. *Recording.* Harness² has no counterpart. gptr records coaching as visible text in the
   document, which follows gptr's rule that everything replayed is visible.

---

## Part 3. Design

### 3.1 The harness object (NEW export `gptr_tailor()`)

A harness is a function of class `c("gptr_harness", "function")`. Its environment is gptr's
namespace, and its body is one line:

```r
function(...) harness_call(sys.function(), sys.call(), parent.frame())
```

Everything else is in one attribute, a plain list:

```r
list(args = list(mode = "auto", extensions = my_hooks),    # your fixed peter() arguments, as values
     rules = NULL,                                          # your own data rules, never on a surface
     coaching = list(note = "", skills = list(), review = NULL, rules = NULL),
     record = NULL,                                         # counts and decisions only
     id = "<random>", gptr = "1.0.0")
```

**Every harness is built on `peter`.** `peter` is resolved from the installed gptr at call time,
so a loaded harness runs today's peter. `gptr_coach()` and `gptr_tailor()` refuse any other
function, and the refusal says to use `gptr_tailor(peter, ...)`. A wrapper that passes `...` on
to peter would lose peter's binding sites, so objects would be captured by value
(R/gptr-capture.R:59-89). It would also turn `envir` into the wrapper's own frame, so the session
would keep no workspace (R/gptr-gateway.R:117-121).

**`harness_call()` (NEW, internal)** rewrites your call rather than forwarding it:
1. It takes your call as written, `survey_peter("Clean ...", survey_2026)`.
2. It replaces the function with `peter`.
3. It adds the fixed arguments. List-like ones (tool modifiers, `extensions`, `plugins`, `skills`,
   and `.opts` by name) are combined with yours, and on single values your call wins. An argument
   that a wrapper of yours passes on through `...` counts as yours; when it must be combined with
   a fixed one, the dots are written out, identifiers resolved as `peter()` resolves them.
4. It adds the coaching and your data rules as one keyed `extensions` factory, built by gptr from
   the validated data (3.2).
5. It attaches one attribute to the rewritten call, `gptr_harness = list(fn = <the name you
   called>, hash = <coaching hash>, call = <your original call>)`, for the document recorder
   (3.6).
6. It evaluates the result in your calling frame.

For `peter`, that call and yours are then the same call. Binding sites, `envir`, `{name}`
interpolation, `gptr_last()`, the plan hand-off, pipes, `lapply()` and `do.call()` all behave as
with `peter()`.

**Continuations.** `s |> survey_peter("And now ...")` passes the factory again. gptr cannot tell
that a call is a continuation without evaluating its first argument, which could run a pipeline
twice. Instead `gateway_register()` (R/gptr-gateway.R:612-637) gets one change: it skips a factory
with a `gptr_key` attribute that is already loaded for that session. That is how it already
de-duplicates specs (R/gptr-gateway.R:567-576). Your own keyed factories benefit too. A factory new
to a session whose prompt is already frozen, such as another harness on a continuation, refreezes
the prompt: the next request is composed afresh with every loaded harness's coaching and the
continuing call's tool modifiers (D-291).

**Fixed arguments are values.** `gptr_tailor()` resolves them once, in your session, when it makes
the harness. For example, identifiers such as `mode = auto` become `"auto"`. It refuses `+name` and
`-name` entries in `plugins`, because those change the filters of the whole R process
(R/gptr-gateway.R:589-606). When the harness is made or loaded, it prints, as R source, every fixed
argument that is not plain data, and `mode = "yolo"`, and always the fixed `extensions` and
`plugins` and a fixed `.opts` holding `system`. `prompt` cannot be fixed: it is each call's task
(D-297). Plain data is `NULL`, text, numbers, logicals and lists of them, with no attribute but
names; so any function, spec, provider, environment or formula is printed (D-289).

**Reading it.** `$coaching` and `$record` are read-only views of the attribute. `$report` returns
the last full report from this R session's memory, keyed by `id`, or `NULL`. To change a harness,
make a new one: `gptr_tailor(h, mode = "edits")`, or `gptr_tailor(h, coaching = list(...))` to
replace the coaching by hand, validated as below. `print()` shows the fixed arguments, the coaching
sizes and the record.

**`gptr_tailor(x = peter, ..., rules = NULL, coaching = NULL, dir = NULL)`:**
- `x` is `peter` or a harness; `...` are fixed `peter()` arguments merged over `x`'s.
- `rules` are your own `never` and `require` rules (3.2), kept in your half. `rules =` and
  `coaching =` replace `x`'s when given.
- The result always gets a new `id` and an empty record. `gptr_coach()` attaches its record after
  building its result this way.
- `gptr_tailor(readRDS(f))` rebuilds the standard body from the attribute, validates the
  coaching, and prints any code the harness carries. It cannot undo what `readRDS()` itself
  already did (see Sharing).
- `dir =` writes files for people to read or keep in git, and returns the harness invisibly. The
  folder is never read back.

```
survey_peter/
  HARNESS.md               fixed arguments (functions shown as source), your rules, gptr version
  NOTE.md                  the note
  REVIEW.md                the review text and its round count
  RULES.md                 the coaching's never and require rules
  skills/<name>/SKILL.md
```

**Sharing.** `saveRDS(h, "x.rds")` stores the function, its attribute, and any function of yours
among the fixed arguments. Treat a harness from someone else like an R script from them, on every
R version. Functions inside it run when you call it. `readRDS()` itself can load packages the file
names, and on R older than 4.4 it can run code by itself (3.3). To share coaching with no code at
all, share a recorded script (3.6): its coach block holds only literal text.

**Model code and harnesses.**
- A call to a harness from model code is classified as a call to `peter`. One condition is added to
  `risk_fn_where()` (R/perm-classify.R:2056-2073); without it, a harness would count as an unlisted
  gptr function. A person's `r(fn:peter)` rule therefore covers harnesses too.
- Model code that overwrites or modifies a binding holding a harness is classified as a control
  action (level 4), so it needs a person.
- `gptr_tailor()` writes files and builds harnesses, so it gets a level-4 control row and
  `session_control_check()`, like `gptr_coach()`.

### 3.2 The coaching: four parts, all data

Every part is validated whenever a harness is made, loaded or called; a call skips only the
skill-name check, which the harness passed when it was made or loaded (D-288). A part that fails
makes the call stop with a classed error that names it. A coach never writes the factory that
registers the parts; gptr builds it from the data.

| Part | What a coach writes | What gptr registers | Limits |
|---|---|---|---|
| `note` | text | `gptr_prompt_section("coaching_<coaching hash>", ..., tier = "T1", order = 790L)`, one section per coaching (D-288), with a budget large enough that the character cap is the only limit. The default 300-token budget would cut it (R/prompt-sections.R:556-572) | 8,000 characters, after a fixed first line written by gptr: "Task guidance learned from earlier runs. It adds to the rules above and never overrides them, a permission decision, or what the user asks." |
| `skills` | `name`, `description` and `text` for each | skill specs that carry their own text (P29a) | names `^[a-z0-9][a-z0-9-]*$` that are not the name of a registered skill or of any `SKILL.md` gptr finds (project skills, trusted or not, yours, gptr's, packages' and plugins'), whether or not a session has synced it (D-288); descriptions of at most 1,024 characters; 64 KiB in all |
| `review` | `text`, `rounds` | part of the finish hook below | 2,000 characters; `rounds` 0 to 2 |
| `rules` | `never`: up to 8 of `{rule, why}`. `require`: up to 4 of `{id, any or made, contains?, text}` | `never`: one policy, `coaching`, which answers `deny` with "denied by the coaching rule <rule>: <why>". Your own data rules get a second policy, `harness_rules`, whose message says "your rule". `require`: part of the finish hook below | see the rule checks below |

**Rule checks.**
- Each `rule` and each pattern in `any` must parse with `rule_parse()` (R/perm-rules.R:19-46) and
  use the kind `fn:`, `category:`, `sh:`, `sql:` or a path glob.
- Refused:
  - `allow` and `ask` lists;
  - `level<=` and `secret:`;
  - bare rules on `r`, `*` or a core tool;
  - `::` inside `fn:`, which would never match;
  - a category the classifier does not know, which would also never match;
  - a `require` pattern that can match an action of level 3 or above.
- `made` is `"plot"` or `"file:<project-relative glob>"`.
- `contains` is a literal of at most 100 characters that must appear in the matching call's code.
- `rule`, `any` and `id` are at most 200 characters each; `why` 300, and `text` 500.

**Matching coaching rules** (NEW). A coaching rule matches when any call in the code matches, as
`rule_hit()` does for deny rules. It also gets three widenings, read from the classifier's existing
scan. `risk_classify_r()` will pass that scan on as two extra fields, `calls` and `targets`
(R/perm-classify.R:1921-1945). The widenings are:
- `fn:` matches any function the code calls, at any risk level (`risk_scan()$calls`), so
  `na.omit`, `read.csv`, `plot` and `sample` can be named.
- A path glob on `write` or `edit` also matches the files that R or shell code writes, deletes or
  downloads to. That is the union of `targets$files` and the `path` of every flagged file-write,
  file-delete and network row, each normalised as `rule_call_path()` does (R/perm-rules.R:76-84).
  This covers `peter$write`, `peter$edit`, `system()` and `peter$sh` writes.
- `category:network` also matches reads from a URL.

Two fixes go with these widenings:
- The scan also merges the `calls` and `targets` of workspace functions defined in an earlier call
  (R/perm-classify.R:2344-2348). Without this, a helper defined one turn earlier would hide its
  calls.
- Your own permission rules keep today's semantics, because widening an *allow* rule would loosen
  it.

**The finish hook** (written by gptr) serves `review` and `require` together. It acts only in the
harness's own session, so it never reaches sub-agents.
- On `tool_result`, it marks a requirement met for this run when a matching call returns without
  error. For `made = "plot"`, it reads the result's plot count. For `made = "file:..."`, it looks
  for a matching file changed since the run started, walking at most 5,000 entries.
- On `turn_end` with a final answer, it sends the texts of the unmet requirements, then the review
  text, as one follow-up (`ctx$send(text, as = "follow_up")`, R/ext-api.R:397-402;
  R/agent-loop.R:78-98). It sends at most two per run, counted by `event$run`. It sends nothing:
  - when the run is ending as blocked, aborted or at the turn limit, where a follow-up would wait
    for the next run;
  - in a run with `.opts$returns`;
  - after a refusal by your own rules or by a person. Coaching denials do not count as refusals.
- On `agent_end`, it records the unmet requirement ids as a notice ("This run finished without:
  save-results") and as a session entry. A run's status never changes, because no hook can set
  it.

**Text checks for every text part:**
- valid UTF-8;
- no control, bidirectional or zero-width characters other than newline and tab, and no format,
  line separator, paragraph separator or Unicode tag characters (D-288);
- no tag naming one of gptr's own blocks (a fixed list that includes `coaching`) or any
  `coaching_` name;
- none of gptr's own wordings for a message from the person or an extension
  (R/agent-loop.R:170-181).

The coaching may never contain R functions, file paths outside `made`, tool definitions, models,
modes, budgets, MCP servers or settings. A coach reply with anything else is invalid.

**Reach into sub-agents.** Every policy, and so every `never` rule, binds the sessions a harness
session starts, however they are started:
- When gptr collects the policies for a call, it includes the rank-0 policies of every ancestor
  session, following the parent chain. `worker_registry()` receives the same ancestor ids. This
  covers model code calling `peter()`, teams and fan-outs, whose children have a container session
  as their parent. It replaces revision 2's plan to copy policies at R/subagent-backends.R:229,
  which would have missed those children. It also closes the same gap for your own
  `extensions =` policies.
- `nested_rules()` evaluates every `rules`, `coaching` and `harness_rules` policy, and in a
  coaching run the `fence` (3.3), and keeps the strictest answer. Today it consults only the first
  record (R/agent-dispatch.R:466-485). It is also applied to nested `script`, `write` and `edit`
  calls, not only shell calls (:440), and a shell call's `wd` is part of the code it judges
  (D-281, D-284).

### 3.3 Each session in its own R process (NEW)

gptr's worker backend already starts R children with a fixed bootstrap (R/proc-rscript.R:19-31).
It also:
- ships the person's registered records, plugins and filters (`worker_registry()`,
  R/subagent-worker.R:362-381);
- rebuilds fake providers (`worker_spec_revive()`, :183-192);
- spawns, kills and cleans up children as jobs (:539-616).

A new bootstrap entry, `child`, sits beside `worker_main()` and reuses those parts. Where the
worker calls `run_start()` on a sub-agent, the child calls a harness. The parent schedules children
with `subagent_schedule()` on the worker pool (R/subagent-team.R:17-63). The pool's size is the
existing option `gptr.subagents.max_workers`, which defaults to `min(4, cores - 1)`. Interrupting
`gptr_coach()` kills every child.

**Sent to a run's child** (as data, in a private 0700 folder, over the trusted parent-to-child
path):
- the harness, with its arguments already resolved to values;
- your `...`: the interpolated prompt, your objects under their names (written once per call to one
  file that every run reads), and other `peter()` arguments as values. An object without a name R
  can use, such as the `..2` that `do.call()` gives a value, is bound under a name of its own and
  passed under its label;
- the resolved model, with its provider record (base URL, headers, region and compatibility
  settings) resolved in your session. Otherwise Azure, Bedrock and locally configured endpoints
  could not be reached from the child;
- `worker_registry()` and your effective permission rules (`perm_rules_effective()`), loaded into
  the child's process rule store, with project-relative path globs anchored to your project;
- copies of your project's instruction files;
- the gptr options children never receive today: `critical_guard`, `secret_guard`,
  `protect_size`, `max_turns`, the `subagents.*` limits, and your `replay` mode;
- the parent's pid, so that an orphaned child exits;
- the registered secrets whose values the job and its objects hold, which the child registers to
  redact only, so they reach no model raw and resolve no credential (D-295).

A **coach's child** receives no registry, no extensions and no tools: only the coach's prompt, its
model and the reply schema.

Objects that cannot cross processes, such as external pointers and connections, are refused before
anything starts. The child's environment variables carry only that session's own provider key
(`child_env()`, R/auth-childenv.R:179-231), or, on a plan route, only that CLI's login variables
(3.7). Keys saved with `gptr_login()` stay readable in the child through gptr's credential store,
as they are for workers today.

**In the child,** `child_main()` (NEW, internal):
- sets `gptr.interactive = FALSE` and `noninteractive_ask = "stop"`, so a step that needs a person
  ends the run `blocked` (R/agent-dispatch.R:689-710). It also turns recording off;
- sets an internal flag that makes `provider_stream()`, the one function every chat model request
  goes through, refuse a model outside the allowed kinds (1.5). System 1 classifier calls do not go
  through it, so a run may call System 1: they send only the judged values and keep the egress check
  (D-300). This covers a router's choice and its fallback, `ctx$set_model()`, sub-agents with their
  own model, System 1 emulation and compaction;
- runs every sub-agent inline: `backend = "worker"` is rewritten to `"inline"`, so the fence, the
  flag and the streamed events cover sub-agents in one process;
- makes a fresh folder under its temporary directory to be its working folder and project root;
- registers a fence policy written by gptr, for the whole child process. It denies:
  - writes and edits whose classified path lies outside the child's temporary folder, which holds
    the run's folder (with the widening above); a relative path is read from the run's folder;
  - a change of working folder to anywhere but the run's folder itself, written as an absolute
    path: `setwd()`, `withr::with_dir()` and `local_dir()`, `xfun::in_dir()`, any `wd =`
    argument, and `cd`, `pushd`, `chdir` or `Set-Location` (in any letter case) in any string of the
    code. A changer's name counts as a move only where R calls it, where `do.call()`, `match.fun()`
    or `get()` names it, or where the classifier reads it passed on as a value that leaves the
    project or goes to a folder the code computes (D-297). A subfolder is denied too, because after
    moving into one a `../` path that the classifier resolved inside the folder would lead outside
    it. So the working folder never moves, and the paths the classifier resolves hold (D-284);
  - every `peter$script()` call and `script` tool call. R code never shows the interpreter, and a
    script may start R with code gptr cannot read; `peter$sh("python x.py")` still works (D-284);
  - every call in the `install` category, which gains a row for `R CMD INSTALL` in
    `inst/extdata/risk-commands.csv` (today it is classified as a plain process);
  - `Rscript -e` and other R child processes whose code gptr cannot read;
  - code gptr cannot classify, and reads of the CLI login files and the keychain (3.7).

  The fence is not a sandbox: it cannot fence a path the classifier cannot see;
- registers hooks that stream, to its standard output, each tool call that actually ran
  (`tool_execution_end` without `refused`) with its risk level, each refusal, and each unmet
  requirement;
- runs the harness and catches the condition peter signals for `blocked`, `budget`, `max_turns`
  and `error`;
- writes its result as **plain JSON text** in one fixed shape, `list(id, status, reason, text,
  turns, usage, transcript, first_user, risk, refusals, unmet, files, plan, limit, checks, error,
  value, objects)` (`child_result_new()`):
  - status, reason, last text, turns and usage rows;
  - the rendered transcript, clipped as an untrusted observation, for the coaches and the report,
    and the first user message on its own (`first_user`), which is the task the coaches and the
    judge see;
  - the highest risk that actually ran, the refusals, the unmet requirements, and the files written
    to its folder, clipped;
  - the last plan reading, a plan limit's reset time, the message of a failed CLI check, and the
    error;
  - last, the realised value and created objects, through `session_value_get()` and never as a
    session object. Each is `{type, len, data, na, names, dim, levels, tz, nrow}`, where `type` is
    one of logical, integer, double, character, factor, Date, POSIXct, data.frame, list or
    summary. Numbers are base64 of `writeBin()` in little-endian order, so they are exact,
    including `NA` versus `NaN` and `-0`. Anything else is sent as its printed summary, and so is a
    value these keys cannot rebuild exactly: dimnames, an ordered or NA-level factor, a data frame
    with its own row names, `NA` names, bytes or invalid text. A POSIXct keeps an absent `tzone`.

  The encoder keeps within the parent's limits on depth and on the number of values, so a value
  too deep or too large becomes its summary. A result still over 64 MiB is written again with the
  value and each object as its summary, so every other field arrives (D-290).

**In the parent:**
- The result is read with gptr's `json_decode()`, which calls `jsonlite::parse_json()` with no
  simplification (R/json-encode.R:23-27). That parser can produce only text, numbers, `TRUE` and
  `FALSE`, and lists.
- The parent then caps the file size, the depth and the element counts, rejects unknown keys, and
  rebuilds the allowed kinds itself with `readBin()`, `structure()` and `.POSIXct()`. It sets a
  class only from the fixed list, so a file can never name a class whose methods would run. It
  checks the shape of every field (`status` one string, `turns` a whole number, `usage` a data
  frame with numeric tokens and cost, and so on), so a forged field ends that run as an error and
  never stops the call.
- It never calls `readRDS()` or `jsonlite::unserializeJSON()` on a run's output. **So
  `gptr_coach()` works on every R version gptr supports (4.2 and later).**
- The child's standard output is read by the child entry's own line reader. It parses only its own
  three event types and never opens a question or a permission prompt. The worker's reader
  (R/subagent-worker.R:443-483) is not reused, because model code can print lines to that same
  output.
- Model code ran inside the child, so it could rewrite the result file or print false lines. The
  parent trusts each report only in the safe direction:
  - For a **final**, it keeps the worse of the stream and the file: the higher risk, every
    refusal, every unmet requirement.
  - For the **starting runs**, whose highest risk sets the ceiling a final must not exceed, it keeps
    the lower risk.

  A run that sets out to forge its whole report could still do so. Coaching that is kept is text,
  printed to you in full, and it runs under all of peter's checks.
- Usage rows that pass gptr's usage check are charged, each request once, to the session of the
  run the call is part of, or else to the session-less log, so `gptr_usage()` shows what coaching
  spent. Those rows stay in memory: the session file takes only rows its own session made, so a
  resumed session lacks the coaching spend charged inside a run.

**Why `.rds` is not used, in plain words.** An `.rds` file is not only data. R's save format can
also hold a "do this later" note, which R calls a *promise*. Before R 4.4, a file could be built so
that what `readRDS()` hands back is such a note. The moment your code touched the result, R carried
out whatever the note said: any command, with your permissions (CVE-2024-27322). R 4.4 refuses to
hand back such a note, but only at the top of the file. Even on R 4.4, reading an `.rds` file can
load packages, and the file can hold functions and *active bindings* that run code when used.
Reading an `.rds` therefore always means trusting whoever made it. A run's result is made by a
process where model-written code ran, so gptr reads it as JSON text, which cannot run anything.

### 3.4 `gptr_coach()` (NEW export)

```r
gptr_coach(..., harness = peter, check = NULL, coach = NULL, k = 1L, strategy = "parallel",
            focus = c("procedure", "domain"), surface = c("note", "skills", "review", "rules"))
```

`...` is exactly what you would give the harness: the prompt, your objects, and any `peter()`
arguments, such as `mode`, `model`, `budget` and `tools`. Every run gets them, and `budget` also
caps each coach session. They apply to this call's runs only and are not kept in the result.

`surface` defaults to all four parts, `c("note", "skills", "review", "rules")` (P29g shipped with
the first release; see the settled questions at the end of Part 4).
No argument of `gptr_coach()` shares a name with one of `peter()`'s.

**First, the document.** Right after `session_control_check()`, in every replay mode, gptr asks the
document route whether this call has a fresh recorded block (3.6). If it does, the block replays:
no model is resolved, no object is checked, and no process starts. So a recorded coaching replays
on a machine with no keys.

**Then, refused before anything runs** (one classed error each):
- a call from model code during a run (`session_control_check()`, R/session-object.R:1214-1230,
  plus a level-4 control row);
- a harness that is not `peter` or a harness;
- a run, coach or judge model outside the allowed kinds (1.5). gptr accepts a model when its
  record type is `chat` and its transport is HTTP, or in-process for `gptr_fake_provider()`, or
  when it is gptr's own `claude-cli` or `codex` record (registered by `builtin:cli`) and that CLI
  passes the preflight in 3.7. A user-registered process adapter that imitates a CLI is refused.
  The error names the reason: router, decision model, untested CLI version, or failed preflight;
- any model refused by `replay_guard()` (R/gptr-config.R:1074-1085), checked for every run, coach
  and judge model before any process starts, as the worker backend already does
  (R/subagent-worker.R:410-425). Under `GPTR_REPLAY=replay`, a coaching call that has no fresh block
  therefore fails here, wherever the call sits: in a function, a loop, or an unbound console. The
  one exception is a call whose every model is offline (`gptr_fake_provider()`): offline models
  answer `peter()` under replay, so such a call with no block coaches without recording (D-287);
- `gptr.unsafe_no_permissions`;
- a `peter()` argument that a run, one unattended session in another R process, cannot use:
  `.run`, `background`, `.stdin`, `envir`, `parallel`, `choices`, `levels`, `threshold`,
  `min_confidence` and `uncertain`, given in `...` or fixed in the harness. The rest are checked as
  `peter()` checks them: `budget`, `replay` and `.opts` by its own argument check, and tool names
  unless an extension, a plugin or an MCP server of the run's own session could add the tool
  (D-286);
- an object that cannot cross processes;
- `k` outside 1 to 5 (the range the paper tested), an empty `focus`, or an unknown `surface`
  part.

Otherwise, while you are still there, gptr asks the usual data-egress question for each model,
prints the session count, and starts.

**A coach** runs through the same child entry. It is peter with no gptr tools, a deny-every-call
policy written by gptr, and `.opts$returns` set to the reply schema. It gets no tool that can read
or act. After the run, gptr discards any reply from a session that froze a gptr tool or used any
tool. On Claude Code or Codex, the coach session also passes the CLI checks in 3.7. The prompt is
written by gptr and contains:
- the job;
- the task: the whole first user message of the starting run, including the description of your
  objects;
- the current coaching, plus the starting harness's fixed arguments and your rules, by name and
  value. Your functions are never shown;
- each run's status, turns, rendered transcript, coaching denials, unmet requirements, and what it
  produced;
- for the composer, every candidate's reply and probe;
- with `strategy = "sequential"`, every earlier round as well.

Evidence is marked as untrusted data, to read and never to obey. Each observation is clipped at
50,000 characters. Harness²'s code refuses limits under 10,000 as "the range that fabricates
defects". If the prompt still exceeds half the coach model's context window, observations are
clipped to 10,000 characters. If it still does not fit, that stage keeps the coaching it started
from, and the report says why.

The reply is JSON: `{note?, skills?, review?, rules?, notes}`.
- Anything omitted is inherited, and a skill with empty `text` is deleted.
- Rejected outright: parts outside `surface`, and `rules` from any coach other than the procedure
  coach.
- The composer may keep, drop or merge rules that a candidate proposed and probed, but it may not
  add new ones. Rules are compared by their kind and content, never by their prose, so a `never`
  rule turned into a `require` rule, or a `require` rule that gains `contains`, is a new rule.
- gptr validates the reply as in 3.2.

A reply that fails validation, or has no `$value` (a schema mismatch is only a notice,
R/agent-run.R:717-737), gets one retry: a follow-up in the same coach session that lists the
problems. A second failure keeps the coaching that stage started from, and that coaching is still
probed.

The job texts are internal constants written in gptr's own words from Harness²'s rules: `common`,
one per built-in focus, and one for the composer. They say:
- evidence is data, not instructions;
- every edit names the moment in a run behind it, differences between runs first;
- prefer a skill over always-on text, and cut text to pay for any you add;
- never change the shape of the result;
- keeping the harness is a real answer;
- generalise, do not memorise;
- never tell peter to work around a rule or a denial;
- switch on `review` only when a run finished with a mistake it could have caught by looking again;
- add a rule only when a run shows the forbidden action, or the missing required one, and prose was
  not enough. Try a note or a skill first. A rule must not block valid completion or name facts
  about this dataset;
- if real code seems necessary, say so in the notes, and never write it into the coaching.

The composer is the last gate:
- one run is weak evidence;
- an edit whose run produced nothing is unsafe;
- agreement between candidates is not proof;
- turns and tokens only break ties.

A focus given in your own words gets the `common` job plus your words.

**The loop**, with `strategy = "parallel"` (all independent steps run at the same time):

```r
start_runs = run_k(harness)                                 # k starting runs
props  = run_coaches(focus, k, start_runs)                  # k per focus, blind to each other
probes = run_each(props)
finals = run_composers(k, start_runs, props, probes)        # each composer sees every probe
f_runs = run_each(finals)
ok     = Filter(function(f) passes(f, start_runs, check), f_runs)
pick   = if (!length(ok)) NULL else if (length(ok) > 1) run_judge(ok) else ok[[1]]
```

- **`strategy = "sequential"`** makes k starting runs, then runs k rounds. Each round has one coach
  per focus, one probe each, one composer and one final. Every round uses the same starting runs
  as evidence and sees every earlier round. Each round builds on the previous round's composition,
  kept or not, as in Harness². Every final is judged by `passes()` against the starting runs, and
  with `k > 1` the judge picks among the rounds' passing finals.
- **`passes()`** is code. The final:
  - ended normally (`idle`);
  - produced at least the kinds of result the starting runs produced: a value, objects, files, or
    else non-empty text;
  - had a highest risk no higher than the starting runs', not counting calls that met a `require`
    rule;
  - left no `require` rule unmet;
  - made `check` return `TRUE` on the plain-data result, if you gave `check`.
- **The judge** is a tool-less coach session. It sees only the task and the deliverables of the
  passing finals, under shuffled labels. It never sees a harness, a transcript, a rule or `check`.
  It ranks the finals in Harness²'s order (delivery, conformance, fidelity, consistency, fitness,
  finish) and answers with one label from an enum. If it fails, the first passing final wins.
- If every starting run ends `blocked`, the call stops before any coach runs and reports what
  needed approval. If every starting run ended with an error or took no turns, the call stops there
  too, with the first one's error, since coaching would rest on no evidence (D-286).
- **Result.**
  - Kept: the starting harness with the new coaching and a new record. gptr prints the coaching in
    full.
  - Not kept (`pick` is `NULL`): the starting harness with a new record and the reason.

  The full report goes into session memory under the harness's `id`. When a document is being
  recorded, the result is also written as a coach block (3.6).

### 3.5 Safety: what every harness always inherits

| # | Rule | Enforced by |
|---|---|---|
| S1 | Coaching is data: a note, skill texts, a review text with its round count, and rule strings. A coach never writes R code | validation of every coach reply, and of every harness when it is made, loaded or called; specs built by gptr |
| S2 | Every guardrail is base peter's, plus your own | built-ins no filter can disable; your rules, hooks and policies travel with the harness, into every run and into every sub-agent |
| S3 | Coaching rules can only forbid or remind | the `coaching` policy answers only `deny`; any refusal wins; `require` only sends reminders and reports |
| S4 | The coaching cannot imitate peter's own blocks or hide text, and your own `APPEND_SYSTEM.md` comes after it | the text checks; the fixed first line; order 790 < 800 |
| S5 | Coaches and the judge cannot act or read | a child with no registry or gptr tools; the deny-every-call policy; replies from a session that froze a gptr tool or used any tool are discarded; evidence only inside the prompt; on Claude Code and Codex, the per-session CLI checks (3.7) |
| S6 | Runs cannot touch your session or your objects | each run in its own R process with copies of your objects; results return as JSON text, rebuilt by gptr from a fixed list of plain kinds |
| S7 | Runs are unattended and cannot be rubber-stamped | `interactive = FALSE`, `noninteractive_ask = "stop"`; the child's own line reader opens no prompt |
| S8 | Runs leave your files and libraries alone, by every route gptr recognises | a scratch folder and project root; the process-wide fence; sub-agents run inline; control paths stay level 4 |
| S9 | Every action of a run passes gptr's checks, on every route | the model check before the start; the `provider_stream()` flag during runs; on Claude Code and Codex, the CLI's own tools switched off and verified every session (3.7) |
| S10 | Code decides adoption, which cannot reward riskier behaviour | `passes()`; the risk ceiling from the starting runs; reports read in the safe direction; your `check` |
| S11 | The coaching loop cannot improve itself | its jobs, schema, checks and loop are package code outside the coaching |
| S12 | While a run is active, model code cannot start a coaching call, build a harness or rebind one | `session_control_check()`; control rows; a harness binding is a control path |
| S13 | A harness acts only in the sessions it starts | the coaching is scoped to that session and its continuations; nothing is registered globally |
| S14 | Only the coaching and a count-only record are shared or recorded | the full report stays in session memory; coach blocks hold only the coaching and one line per run |
| S15 | Replay proves no model call | the document route decides first; `replay_guard()` checks every model before any process starts |

**Honest limits.**
1. A run in `auto` mode can still use the network, start programs, and touch files the classifier
   cannot see, exactly like `peter(mode = "auto")`. A separate process is not a sandbox. Use data
   and machines you can afford to have touched.
2. Coaching is drawn from evidence that includes your data, so an instruction planted in that data
   can reach a note. Such an instruction breaks no rule, so neither the fixed first line nor
   `passes()` stops it. Once kept, the coaching runs in your own session on every call. This is why
   gptr prints new coaching in full.
3. Rules read code before it runs. A path or function name that the code computes at run time can
   slip past a `never` rule, and dead code can satisfy a `require` rule. So `require` is a reminder
   plus a report, not proof.
4. A run sees only the objects you pass in `...`, not the rest of your workspace or your attached
   packages. It starts in an empty folder, cannot install packages, cannot write outside its folder
   or move to another folder, and cannot run scripts with `peter$script()`, by the routes gptr
   recognises. It refuses code that writes to a path the code computes or calls a function the code
   computes (F-58, FIX-49). One case still passes: where R cannot tell which argument is the file, a
   literal text passed by position is read as the file, so `write.csv('a', file.path(d, 'x.csv'))`
   writes into `d` (D-297). Give it data as objects, name files by their full path, and install
   what it needs first.
5. A run that forges its own report can lower its reported risk or claim requirements met. The
   parent's safe-direction reading limits this but cannot rule it out. The kept coaching is still
   only text that you read.
6. Unattended runs differ from interactive ones: they have no `ask` tool, and the `extended` preset
   applies only with a person present (R/prompt-sections.R:218, 325-345).
7. Plan routes rely on each CLI behaving as tested.
   - gptr checks every session, so a CLI that adds a tool or ignores a switch is refused. A change
     those checks cannot see would pass.
   - On Codex, "no tools" means "no tool that can read or act". Some models keep a patch tool that
     the read-only sandbox rejects, a code cell with no file or network access, and a clock.
   - Codex reads your own `~/.codex/AGENTS.md` into every session, and gptr cannot switch that off.
   - A run in auto mode on a plan route can still read the plan's login, from the CLI's login file
     or the macOS keychain, through ways the fence cannot see. The fence denies the ways gptr
     recognises (3.7).
8. Harness² measured re-running the *same* task. Whether coaching on one dataset helps on the next
   is untested; phase P29h, which would measure it, is deferred after 1.0 (D-300).

### 3.6 Recording harness calls and coaching (NEW)

This follows gptr's general plan for recordings (dev/spec/03-architecture.md, documents and replay;
dev/plan/P15-documents-replay.md):
- the document is the history;
- everything replayed is visible in the document;
- freshness is decided by content hashes;
- writing needs consent;
- caches hold only answer text, are redacted and are gitignored;
- `GPTR_REPLAY=replay` is the proof, in CI, that a script makes no model call.

No new format, export or option is added.

**One identity: the coaching hash.** It is the first 8 hex characters of
`hash_sha256(canonical_json(list(schema = 1L, note, skills, review, rules)))`. Skills are sorted by
name, and text is normalised as `prompt_hash()` does.
- The coaching is redacted with the persist profile *before* it is hashed, printed or returned. So
  the harness in memory, the printed coaching and the recorded block always agree.
- The hash covers only what coaches change. Plain blocks work the same way: the prompt is part of
  freshness, but the model and mode are not (vignettes/script-as-history.Rmd:326). So editing a
  fixed argument keeps blocks fresh.
- A harness with no coaching always has the same hash, so `peter(` and an uncoached altered peter
  read alike.
- The gptr version is not in the hash, so an upgrade does not stale every recording.

**Which calls count.** The recorder today finds calls by the token `peter` (R/doc-blocks.R:313). It
will count a call head as a harness call when the head is `peter`, `gptr_coach`, or a name bound
to a `gptr_harness` where the call is evaluated:
- `gptr_source()` tests this on its `envir` before each expression (R/doc-replay.R:1388-1420), and
  the user log tests it on `globalenv()` (R/env-history.R:23-29).
- Static readers such as `gptr_blocks()` use `peter`, `gptr_coach` and every name that a
  `harness=` or coach-block header in that document declares.
- The scan memo key includes the set of heads (R/doc-blocks.R:276-292).
- Every other place that names `peter` takes the same heads:
  - the transcript writer (R/doc-formats.R:444-451);
  - `gptr_export()` (R/doc-export.R:12-18, 187, 245);
  - the nested-call parts (R/doc-blocks.R:1177-1209);
  - the notebook sidecar codec (R/doc-io.R:634-645). Today the codec refuses any call identity that
    is not `peter`; it will accept any bare-name head, which it never evaluates.
- `doc_locate()` takes `call0`, the head and the coaching hash from the call's `gptr_harness`
  attribute (3.1). So `survey_peter("Clean")` and `peter("Clean")` in one file each own their own
  block, under `source()`, Rscript and the IDE.

**(a) Harness calls.**
- A harness-call block is an ordinary `peter()` block with one more header key,
  `harness=<name>:<hash>`. Team and fan-out blocks get it too.
- A block is fresh only when its prompt, its interpolated `{name}` values, its kind (coach or not)
  and its coaching hash all match. `doc_block_status()` and `doc_decide()` gain those comparisons.
- Replay is unchanged: no model is called, so the coaching is not used. The harness must exist
  under its name for R to evaluate the call; the coach block above it creates it on replay.

**(b) Coach blocks.** A coaching call is recorded only when its statement is exactly
`<name> = gptr_coach(...)` or `<name> <- gptr_coach(...)`. Any other shape is not recorded, and
gptr says once why. The statement owns one block of kind `coach` (the example in 1.10).
- **Header:** model, date, prompt, args, tokens, cost, `harness=<name>:<new hash>`,
  `start=<starting name>:<starting hash>`, `coach=<model>`, `gptr=<version>`.
- **Body:** one assignment, `<name> = gptr_tailor(<starting name>, coaching = list(...))`. The
  coaching is the full coaching of the result, not a difference. It is followed by one `## Run:`
  line per run (status, turns, risk, unmet requirements) and a `## Decision:` line.
- **Safe writing.** Every text is written with gptr's own string writer `doc_str_literal()`
  (R/doc-blocks.R:28), never as a raw string. Every `##` line goes through `doc_one_line()`
  (R/utils-text.R:243-246). Before writing, gptr parses the body back and refuses to write unless
  it rebuilds the same coaching hash. A note that tries to end its string and add R code therefore
  cannot reach the script.
- A coaching call whose result was **not kept** is recorded too, as `<name> = gptr_tailor(<starting name>)`,
  so the decision replays without seven sessions.
- A coaching call that errors or is interrupted writes nothing, as for a `peter()` run that does not end
  normally.
- The starting harness is written by its name. gptr records a coaching call only when `harness` is
  missing, `peter`, or a plain name. Fixed arguments and your functions are never written.
- R Markdown, Quarto and Jupyter get the same body as an agent chunk or cell. Rscript and Jupyter
  use the existing deferred and pending writers.
- **Path.** `gptr_coach()` builds a peter-style call record with peter's own capture helpers. It
  reaches documents only through two services registered by `builtin:documents`, as the team routes
  already use `doc.replay`:
  - `doc.coach(call)` locates the call and runs `doc_decide()`;
  - `doc.coach_block(site, harness, record)` redacts and writes through `doc_upsert()`.

  Consent, locks and the `document_write` event are reused. A coaching call has no parent session, so
  only process-wide `document_write` hooks see coach blocks. If the write was patched by such a
  hook, `gptr_coach()` returns the harness that the written body defines.

**Replay of a coach block, with no model, no keys and no R processes:**
1. gptr parses the body with `doc_parse_text(keep_source = FALSE)` and never evaluates it. It passes
   each string through `as_utf8()`, so a C locale cannot change the hash.
2. A closed walker accepts exactly one `<name> = gptr_tailor(<name>, coaching = ...)`. The
   coaching must be built only from `list()` and `c()` calls, with named or unnamed arguments, down
   to literal text, numbers, logicals and `NULL`. This is the same discipline as `doc_unquote()`
   (R/doc-blocks.R:44-69).
3. It validates the coaching with the rules in 3.2.
4. `gptr_coach()` returns exactly the harness the body builds. The body then runs as ordinary
   document code and assigns the same harness.

If the body has been hand-edited into something that is not literal, the call returns the starting
harness with a notice. The body's own code then defines the harness: as everywhere in gptr's
recordings, your code wins.

**Decisions** use the existing `doc_decide()` table, plus three rules:
- A coach block is fresh when its prompt, its interpolated values, its kind and the hash in
  `start=` (the starting harness's coaching) match. A hand-edited body is caught by the block's
  existing `sha=`.
- Under `auto`, a stale coach block asks before coaching again, showing the session count, when a
  person can answer. Otherwise it replays with `replay_downgraded`. `record` and `live` coach again.
  This departs from plain `peter()` because of cost and non-determinism.
- Under `replay`, a coaching call with no fresh block fails in `replay_guard()` before any egress
  question or process (3.4), unless it has no block and every model is offline; then it coaches
  without recording, as `peter()` lets offline models answer under replay (D-287).

`gptr_export()` refuses a document that holds a coach block, with a named reason, because a coach
block has no session turn to export.

**Drift needs no extra machinery.**
- A later call names an earlier harness by its R name. Freshness is checked against the hash of the
  harness object actually called, so renaming, reassigning or loading from `.rds` cannot
  misattribute a block.
- Coaching block A again changes A's hash. That makes A's harness-call blocks stale, and every coach
  block whose `start=` names A, and so on down the chain.
- Under `replay`, all of these become `stale_block` errors: a clear signal in CI.

**Console transcripts.** The first time a harness is coached or called in a transcript, it is
written once as `h_<id> = gptr_tailor(peter, <plain-data fixed arguments>, coaching = list(...))`.
- That definition goes through the same safe writer, redaction and `document_write` event as the
  block.
- Fixed arguments that are R functions cannot be written. A flag line names them, as the secrets
  flag does.
- Calls are then written `s_<hex> = h_<id>("prompt", <context names>)`.
- `check` is never recorded.

**Privacy.** A script receives only the coaching and one line per run: the same text gptr prints
when it keeps new coaching. A transcript also receives your plain-data fixed arguments. Run
transcripts, values, objects, coach replies, the composer's reasons, `check` and file lists are
never written. The runs' session files are deleted with their folders, so coach blocks carry no
`session=` and add nothing to the answer cache. The coaching may still carry facts drawn from your
data, and committing the script publishes them.

**Size.** At most about 85 KB of ASCII per coach block, bounded by the limits in 3.2.

**Contract changes** (04-interface-contract, 11.5 and 7.0):
- block kind `coach`;
- header keys `harness`, `start`, `coach` and `gptr`;
- the `kind` row, which today covers only `team` and `fanout`;
- the ownership text, which names only `peter()` calls;
- the transcript rows for `h_<id>` definitions and harness statements;
- the sidecar's call-identity rule;
- the services `doc.coach` and `doc.coach_block`.

### 3.7 Subscription plans: Claude Code and Codex (NEW)

Many people's only tokens are a Claude Pro or Max plan, used through Claude Code, or a ChatGPT
plan, used through Codex. Both routes work for runs, coaches and the judge. The approach is the
same on both:
1. switch off the CLI's own tools;
2. leave only gptr's tools, over gptr's existing MCP relay, for a run, and nothing for a coach or
   the judge;
3. check every session, and refuse it when a check fails.

**Common to both routes.**
- **Which records.** Only gptr's own `claude-cli` and `codex` records, registered by
  `builtin:cli`, are accepted. A user-registered process adapter that imitates them is refused.
- **Preflight**, once per CLI path and version, cached:
  - The version must be at least the oldest one gptr was tested with: claude 2.1.296 and
    codex-cli 0.157.1. A newer version runs with a one-line notice. The checks on every session
    protect it, because they fail closed. Claude Code updates itself, and gptr ships through CRAN,
    so a list of exact versions would refuse coaching after every update.
  - For Codex, `codex features list` run with the same switches must report every switched-off
    feature as off and `hooks` as on. This command makes no model call, and an unknown feature name
    makes it fail, so a renamed switch fails closed.
- **Each session starts clean.** Its working folder is a fresh folder. The CLI saves no session
  and uses no memory. The person's own CLI settings, hooks, plugins and skills are not loaded.
- **Logins in child processes.** A child receives only the login variables its route needs:
  - Claude Code: `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`,
    `CLAUDE_SECURESTORAGE_CONFIG_DIR` and `CLAUDE_CODE_GIT_BASH_PATH`;
  - Codex: `CODEX_HOME`. A person who keeps their Codex login in the OS keyring has
    `cli_auth_credentials_store` set in `$CODEX_HOME/config.toml`, which `--ignore-user-config`
    skips. gptr reads that one setting and passes it with `-c`.

  Today's worker allowlist drops these (R/auth-childenv.R:46-62), so a person with a setup token
  or a second account would sign in to the wrong account, or not at all. On macOS, the default
  Claude login is in the keychain, and the child reaches it through `USER` and `PATH`, which are
  already kept. In a run's child, these variables are copied into the CLI's own environment and
  then removed from R's (`Sys.unsetenv()`) before the harness runs. That only hides them from
  `Sys.getenv()`. The run's fence also denies reads of the CLI's login files and the keychain
  commands that gptr recognises (honest limit 7). Variables that would switch billing to an API
  key, such as `ANTHROPIC_API_KEY`, are removed as they are today.
- **Structured replies.**
  - On Claude Code, gptr will honour `.opts$returns` by appending its own returns instruction to
    the last user message (`adp_returns_instruction()`, R/provider-anthropic.R:876-881). Today the
    claude route ignores the schema (R/cli-common.R:1115-1120).
  - On Codex, gptr passes `--output-schema` with the schema in OpenAI's strict form: every key
    required, optional keys nullable, and `additionalProperties: false` throughout.

  Either way, gptr still validates the reply itself (3.2).

**Claude Code.** gptr already starts the CLI with all of its built-in tools removed (`--tools ""`)
and only gptr's MCP server, so every tool call passes gptr's gate (R/cli-claude.R:20-37;
R/mcp-server.R:192-264). Coaching adds the following.
- **Every session:**
  - flags `--no-session-persistence`, `--permission-prompts none` and
    `--settings '{"autoMemoryEnabled":false}'`;
  - environment `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` and
    `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`, set after the profile's filter so they survive it;
  - never `--resume`: a CLI process that is replaced is started fresh with the whole history;
  - never `--bare` (it cannot use the plan login), `--safe-mode` (it drops gptr's MCP server) or
    `--dangerously-skip-permissions`.
- **Coach and judge:** `--tools ""` and `--disallowedTools "*"`, no MCP server, and
  `--max-turns 1`. Before trusting the reply, gptr checks:
  - the `init` line: an empty tool list, no MCP servers, no plugins, skills or commands, no
    auto-memory path, and `apiKeySource` `none`;
  - the stream: any tool use, any line from a sub-agent, or any permission request kills the
    session and discards its reply;
  - the result: a success, in one turn.
- **Runs:** today's flags (gptr's MCP server only, `--allowedTools mcp__gptr__*`) plus the ones
  above. gptr checks that:
  - the `init` tool list equals exactly the run's gptr tools, and the only MCP server is gptr;
  - any use of a tool that is not gptr's fails the run: a `tool_use` for it in the stream, or a
    non-empty `permission_denials` list in the result. With `--permission-prompts none`, the CLI
    denies such a request itself and never asks gptr. Today such a request would reach
    `perm_check()` at level 2, which auto mode allows (R/cli-claude.R:215-235).

  A call that needs approval also interrupts the CLI's turn at once, so a blocked run stops, as on
  an API route. Today it stops only when the CLI's whole turn ends (R/agent-run.R:1091-1095). Every
  action then passes gptr's gate, the fence, the rules and the risk tally.

**Codex.** Codex's own shell cannot be gated reliably:
- Its tool hooks let a command through when the hook fails or times out, and they do not see the
  command's working folder. OpenAI calls them "not a complete enforcement boundary".
- Its approval protocol needs an experimental server that OpenAI does not support for production.

So coaching switches the shell off, and every Codex session gets:
- `codex exec --json --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check`, with
  `-s read-only` always (even in auto mode) and `-C` set to the session's fresh folder. Today's
  adapter uses workspace-write in auto mode (R/cli-codex.R:65-78);
- never `exec resume`: an ephemeral thread is not saved, so a follow-up such as a coach's retry or a
  review reminder starts a fresh `codex exec` that carries gptr's instructions and the whole
  history, as the adapter already does for a new thread (`pcli_codex_prompt(fresh = TRUE)`,
  R/cli-codex.R:84-91, 273);
- `--disable` for `shell_tool`, `unified_exec_tty`, `view_image`, `multi_agent`, `apps`,
  `plugins`, `tool_suggest`, `image_generation`, `memories`, `goals`, `sleep_tool`,
  `skill_search`, `browser_use` and `computer_use`;
- `-c` settings that turn off web search, `request_user_input`, agents and skills, and Codex's
  extra permission, environment and app instructions;
- a `PreToolUse` hook that gptr ships, passed with `-c` and `--dangerously-bypass-hook-trust`:
  - For a coach or the judge it denies every tool. For a run it allows only `mcp__gptr__*`, after
    parsing the hook's JSON input properly.
  - It logs every attempt it denies. It also writes one start line when the session starts, so an
    empty log can be told apart from a hook that never ran.
  - gptr refuses to start if `$CODEX_HOME/hooks.json` exists (by default `~/.codex/hooks.json`),
    because the bypass flag would run those hooks too. Hooks an administrator puts under
    `/etc/codex` always run, as managed settings do for Claude Code.

What remains for the model on some models is:
- a patch tool, which the read-only sandbox rejects before it runs;
- a code cell, which has no file or network access;
- a clock.

None of these can read or act. Prefer a model without code cells, such as gpt-5.5, when the plan
offers one.
- **Reading the events.** Codex also reports warnings as events of type `error`, and the bypass
  flag always adds one. These are allowed, and gptr requires the bypass warning as proof that the
  flag took effect. What gptr rejects are tool events (`command_execution`, `file_change`,
  `web_search`, `collab_tool_call`, `todo_list`, and an `mcp_tool_call` to any server but gptr's)
  and a failed turn.
- **Coach and judge:** no MCP relay, plus `--output-schema`. gptr keeps the reply only if:
  - the events hold no tool event and the turn completed;
  - the hook log holds its start line and no denial, which catches the tool kinds the events leave
    out;
  - there is exactly one final message, and it validates.
- **Runs:** gptr's MCP relay is kept, so the run acts only through gptr's tools, and every action
  passes gptr's gate, the fence, the rules and the risk tally. Any tool event other than a call to
  gptr's MCP server makes the run invalid. Each denial in the hook log counts as a refusal.
- **Verified live** (2026-10-28, Codex 0.157.1 on a ChatGPT plan): the backend accepts the reduced
  tool set and the strict schema (D-274), and Codex wrote no file holding the prompt despite
  `--ephemeral` (D-276). **Not yet measured:** how well a run does without Codex's own shell (P29h,
  deferred).
- **Later, and cleaner for ChatGPT plans:** OpenAI's "Sign in with ChatGPT", which it offers for
  open-source tools that run locally. On that route gptr would call the model itself, as on any
  API route. It is not built yet.

**Plan limits and accounting.**
- **At most two sessions at once per plan account,** whatever `k` is. More sessions in flight do
  not add capacity, and every one of them is lost when a limit is reached.
- **Before starting**, gptr says in plain words:
  - how many sessions it will run on which plan;
  - that they use the plan's 5-hour and weekly limits, which the person's other use shares;
  - the last plan reading gptr has, with its age, including readings the coaching runs took
    (merged when newer, checked and clipped);
  - that dollar figures on the Claude route are what the same tokens would cost on the API, not
    charges, and that Codex reports tokens only.

  After the first starting run, it prints a projection of the total from that run's tokens.
- **Reaching a limit:**
  - **Detection.** On Claude Code, a `rate_limit_event` with status `rejected`, or a failed result
    whose text says the session, weekly or model limit was hit. On Codex, an error whose text says
    the usage limit was hit (with a typographic or a plain apostrophe), or that a workspace is out
    of credits or has reached its spend cap. Codex gives the reset time only as local text, which
    gptr quotes.
  - **In the child.** It reports the limit and its reset time in its result. `run_retryable()`
    stops retrying weekly and model-family limits: today only the session limit is excluded
    (R/agent-run.R:190-193, 312-330).
  - **In the parent.** It starts nothing new and lets the running sessions finish. It returns the
    starting harness with a record that says "stopped at <stage>: plan limit, resets at <time>".
    It never waits for a reset and never resumes by itself.
- **Usage credits.** When a Claude session starts drawing on paid usage credits (`isUsingOverage`,
  or `errorCode` `credits_required`), the `gptr_coach()` call stops the same way.
- **Accounting.** Plan usage and billed API dollars are reported separately and never added
  together. A plan row on Claude reads "API-equivalent $X, not billed". On Codex, only tokens are
  reported.
- **Mixed setups.** These are allowed, for example coaches on a Claude plan and runs on an API key.
  Each plan account is counted separately, and gptr asks the data-egress question for every vendor
  involved.

**Terms**, as the vendors state them (checked 2026-10-28):
- **Anthropic** lets a person use their own plan with the unmodified `claude` program, including
  `claude -p`. Such use counts against the plan's limits, which assume "ordinary, individual
  usage". Its Agent SDK page says third-party developers may not offer Claude.ai login or rate
  limits for their products without approval. gptr never handles the login. gptr's architecture
  already requires the maintainer to ask Anthropic before advertising the plan route
  (dev/spec/03-architecture.md:2515-2516), and that covers plan coaching too.
- **OpenAI** lists `codex exec` and scripting as plan features, and recommends API keys for
  automation.

---

## Part 4. Implementation phases

Every phase is written test-first with `gptr_fake_provider()`, runs offline, follows house style
(`=`, `|>`), and adds no Imports. Ids follow the P26 precedent: this file becomes the spec
amendment, with a plan `dev/plan/P29-gptr-coach.md`, D-273 and IC-83 onward.

| Phase | What | Main acceptance tests |
|---|---|---|
| P29a | Core changes:<br>- skill specs that carry their own text and are found per session (R/skill-discover.R:390-473, R/tool-read.R:435);<br>- a keyed factory loads once per session;<br>- `risk_fn_where()` treats a harness as `peter`, and rebinding a harness is a control action;<br>- ancestors' policies bind every sub-agent;<br>- `nested_rules()` keeps the strictest answer and covers nested writes;<br>- `risk_classify_r()` passes on `calls` and `targets`, including those of earlier helpers;<br>- the `R CMD INSTALL` row;<br>- the `provider_stream()` model flag | a session skill opens in that session only; a keyed factory loads once; `h()` from model code is denied by `r(fn:peter)`; a person's `extensions =` policy binds a nested `peter()`, a team member and a fan-out child; `R CMD INSTALL` is in `install`; a disallowed model is refused mid-run |
| P29b | `gptr_tailor()`, the note, skills and review (3.1, 3.2), and recording of harness calls (3.6 a) | a harness call behaves like the same `peter()` call and records a block with `harness=`, which replays with zero requests and goes stale when the coaching changes; `survey_peter("X")` and `peter("X")` in one file own separate blocks under `source()`, `gptr_source()`, Rscript, the IDE and a notebook; fixed arguments merge as stated; a continuation loads the coaching once; review counts per run and stays out of sub-agents; every invalid part is refused; `.rds` round-trips; `dir =` writes the files |
| P29c | the `child` entry and the JSON transport (3.3) | a run returns plain data with exact doubles, factors, Dates and data frames; a closure, environment or unknown class is reduced to a summary; it gets your rules, hooks and endpoint settings (an Azure and a local `base_url` test); an ask ends it `blocked`; writes outside its folder, `setwd()`, `R CMD INSTALL` and `Rscript -e` are denied, in sub-agents too; a worker sub-agent runs inline; a printed fake `ask` line opens no prompt; a forged low risk in a final's file loses to the stream; a forged high risk in a starting run's stream does not raise the ceiling; at most `max_workers` children run; interrupting kills them all |
| P29d | `gptr_coach()` at `k = 1`, and coach blocks (3.4, 3.6 b) | Harness²'s demo ported: a fake solver that is wrong unless its note holds the fix, and a fake coach that writes it. Also:<br>- exactly 4 runs and 3 coach sessions, with the coaches and the probes run in parallel;<br>- a retry stays in the same session;<br>- an emptier or riskier final is not kept;<br>- `check` decides and never reaches a coach;<br>- every refusal;<br>- a fresh coach block replays with no key, zero requests and zero processes, and rebuilds the same coaching hash;<br>- a note holding `)-"` and R code is written as a string and never runs;<br>- kept and not-kept both replay;<br>- a hand-edited note replays and makes later blocks stale;<br>- under `GPTR_REPLAY=replay`, a coaching call with no fresh block on a model that is not offline fails before any process starts, even inside a function;<br>- no run data is written |
| P29e | Claude Code and Codex plans (3.7) | **Offline, with gptr's fake CLI.** Each of these is refused: an `init` that lists a built-in tool, an auto-memory path or a plugin; a stream that uses a tool that is not gptr's; a Codex event of another kind; a hook-log denial, or a missing hook start line; a feature that a preflight reports still on; a non-empty `permission_denials`. A Codex warning event is accepted. A second turn on Codex (a coach retry, a review round) starts a fresh `exec`. The plan-limit messages end a `gptr_coach()` call with "stopped at ... plan limit". At most two plan sessions run at once.<br>**Live, per CLI (`GPTR_LIVE_TESTS`).**<br>- A coach from a child process has no tools and returns a valid reply.<br>- A coach told to read `~/.bashrc` and run a command replies with text only.<br>- The CLI saves nothing for the session.<br>- A run in auto mode acts through gptr's tools, and a write outside its folder is refused and reported.<br>- A run that needs approval ends `blocked` at once.<br>- Sign-in works from a child process for each kind of login, including a Codex keyring login. |
| P29f | `k > 1` and `strategy = "sequential"` | the counts match the formula; composers see every probe; rounds share the starting runs; the judge sees only passing finals under shuffled labels |
| P29g | coaching rules and your own data rules (3.2) | each of the nine examples in 1.8 matches or misses as stated, including `peter$write`, `system()` and a helper from an earlier turn; a `never` rule denies in auto and yolo, in nested shell calls, and in every kind of sub-agent; a reminder is sent at most twice and never at the turn limit; a `require` rule that saves a file can be kept; an unmet requirement fails `passes()`; only the procedure coach may write rules and the composer cannot add one; inert rules (`fn:pkg::f`, an unknown category) are refused |
| P29h | live calibration (dev only, `dev/bench/coach/`; deferred after 1.0 and not built, D-300) | on 2 or 3 real tasks with deterministic checks: coach on one dataset, then compare the starting and coached harness on new data, three runs each, with cost, on an API key and on each plan. It decides whether the later items are worth building |
| later | only if P29h shows a need | best-of-k as a coaching part; "before X, do Y" ordering rules; sub-agent definitions as coaching; routers with a declared list of models; copying chosen project files into each run's folder |
| later | on its own merits | Sign in with ChatGPT, a route where gptr calls the model itself on a ChatGPT plan |

**Separate items for the maintainer** (not part of P29):
- **The worker backend reads its child's result with `readRDS()`** (R/subagent-worker.R:537),
  from a process where model code ran. Documented in `?gptr_security` and kept by decision (D-300),
  with a ledger row. On R 4.2 and 4.3 that is the CVE-2024-27322 pattern. On every version, the
  exported objects can carry code by design. The status and text could move to the JSON line the
  worker already sends (:318). For the exports, either document the trust they require or gate them
  on R 4.4 or later.
- **`risk_control_env`** lacked `R_USER_CONFIG_DIR`, `HOME` and `XDG_CONFIG_HOME`, so in `auto` mode
  `Sys.setenv()` of one moved gptr's whole configuration. Fixed by FIX-36 (D-272):
  `risk_control_env()` (R/perm-classify.R:1906-1916) holds them, `APPDATA` and `USERPROFILE`; the
  data folder (`R_USER_DATA_DIR`) moves nothing gptr keeps.

**Footprint:**
- two new exports, taking the count from 64 to 66: `gptr_tailor` and `gptr_coach`. Both keep the
  `gptr_` prefix (D-28), so they sit with gptr's other exports. `peter()` stays the single gateway
  (contract S-1): `gptr_coach()` builds harnesses and takes no prompt for a model of its own;
- one bootstrap entry (`child`), one Codex hook script in `inst/`, two control rows and one
  command row in the risk tables, and the recording contract changes listed in 3.6;
- about 1,500 lines of R. P29a to P29e (about 1,300 lines) give coaching at `k = 1` with recording,
  on API keys and on Claude Code and Codex plans. `k > 1` (P29f) and `rules` (P29g) can wait. The
  plan routes (P29e, about 400 lines) are part of the first release, because many people have no
  other tokens.

`peter()` gets no new argument, option, `.opts` key or setting. There is no new Import, and gptr's
R floor stays at 4.2.

---

## Part 5. Decisions taken, and what is left open

**Decided by the maintainer (2026-10-27, names revised 2026-10-28):**
- the names `gptr_tailor()` (build a harness by hand) and `gptr_coach()` (improve one by coaching),
  so both sit with gptr's other `gptr_*` exports; the starting harness is `harness =`. The starting harness may be
  any harness (made by hand, coached, or received), but not an arbitrary function;
- the result is a harness in memory, and a folder is optional;
- the loop settings are arguments with Harness²'s defaults;
- any model may coach, through the routes in 1.5;
- no budget argument: `budget = ` in `...` applies to each session, as in `peter()`;
- no library: gptr ships only `peter`. People share harnesses as `.rds` files, or as recorded
  scripts when they want to share no code;
- every session runs in its own R process, for safety and for parallel runs;
- `check` stays;
- recording of harness calls and coaching is designed now and built in P29b and P29d.

**Decided by the maintainer (2026-10-28):**
- coaching must work on Claude Code and Codex subscription plans, for runs, coaches and the judge,
  in the first release (3.7, P29e).

**Questions settled at implementation (2026-10-28):** the maintainer left these to the
implementer; each answer below is what the code does.
1. `review` and `rules` are on the default surface. They only add checks and refusals, and the
   composer drops them when the probes show no help.
2. Under `auto`, a stale coach block asks before coaching again (`doc.coach` answers `"ask"`), and
   says how many sessions a new coaching starts. Declining keeps the block's harness.
3. A coaching call whose result was not kept is recorded, as `<name> = gptr_tailor(<start>)`, so
   the decision replays. A call stopped at a plan limit is not recorded, because it did not finish.
4. The coaching hash covers only the coaching (`coaching_hash()`: note, skills, review and rules),
   not fixed arguments.
5. On a plan, at most two sessions run at once per plan account (`child_lanes()` in
   `R/gptr-child.R`); once a plan reports its limit, its later jobs are skipped.
6. `k` is not capped per route: it is 1 to 5 everywhere, and the call states the session count
   before it starts, so a person on a plan sees the cost and can decline.
7. A Claude session drawing on paid usage credits always stops coaching (D-282).

---

## Appendix: where the research is

- **Harness² code map:**
  - `core/tree.py`: the harness tree, its surface and validator.
  - `core/recursion.py`: parallel and sequential modes.
  - `core/prompts.py`: the editor, composer and selector texts.
  - `core/selection.py`: blind selection.
  - `core/ledger.py`: the R = 4k and P = 3k counts.
  - `core/library.py`: the library.
- **gptr recording:**
  - dev/plan/P15-documents-replay.md;
  - dev/spec/03-architecture.md (documents and replay);
  - R/doc-blocks.R, R/doc-locate.R, R/doc-replay.R and R/doc-formats.R;
  - vignettes/script-as-history.Rmd.
- **Plan routes** (checked 2026-10-28):
  - the Claude Code CLI 2.1.296 flags, `init` line and environment variables;
  - the Codex 0.157.1 source at tag `rust-v0.157.1`: tools, features, hooks and `exec`;
  - plan limits and terms from Anthropic's and OpenAI's own pages.
- **R deserialization:**
  - HiddenLayer's report on CVE-2024-27322;
  - the R Core statement of 2024-05-10;
  - the fix, commit r86235 (f7c46500), which checks only the value returned at the top level.
- **Literature lessons used:**
  - Meta-Harness and AHE: proposers need full execution traces. The winning changes added context
    and memory, and in AHE also one finish check (+2.2).
  - ACE: whole rewrites collapse context, so edits name only what changes.
  - GEPA and DSPy: keep the program fixed and evolve the text, one change at a time.
  - AFlow, MaAS, MASS and EvoFlow: a few fixed steps beat free code. Sample-and-select and
    check-then-revise carry most of the flow gains. In MASS, prompts gave +11 and the flow +3.
  - Google's 2025 scaling study: returns from extra agents shrank or turned negative once one agent
    alone scored about 45%, except on tasks that split cleanly.
  - "LLMs Cannot Self-Correct Reasoning Yet": revising without an outside signal does not help, so
    `review` asks peter to look again with its tools.
  - The Darwin Gödel Machine, STOP and Gödel Agent: the optimiser must never reach its own checks,
    evaluator or budget.
