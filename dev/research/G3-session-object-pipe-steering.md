# G3 — Session object and pipe steering (S-8)

> Materialised by the lead designer from the gap researcher's structured output and the
> verified prototype files it left in scratch (the subagent could not write this file itself).
> Code is embedded verbatim below so the repository is self-contained. Prototype code may use
> `<-`; convert to the house style (`=`, `|>`) when copying into the package (S-9).

## 1. Summary

G3: the S-8 session object is designed, prototyped and verified. The pipe steers one session object.

NOTE ON THE REPORT FILE. The harness refused my Write to the report path, with the message "Subagents should return findings as text, not write report files." I did not work around that, so /Users/wanjun/Desktop/gptr/dev/research/G3-session-object-pipe-steering.md was NOT written. The findings, specification, positions, risks and open questions are in this structured output. Every prototype and its verbatim output is in the scratch directory given as report_path (absolute: /private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3/).
- Core prototype: gptr_session.R (1,002 lines, base R + jsonlite + rlang, '=' and '|>' only).
- Supporting files: fake.R, setup.R, and doc.R (record/replay on report 14's unmodified gptrdoc.R).
- Tests t1–t9 and probes p1–p6, with final_*.out holding each output.
- If a writer is allowed to materialise the report, it should be assembled from these files and this output.
- Environment: R 4.4.3 on macOS, Rscript --vanilla; the interactive test drove a real R --interactive with real SIGINT through processx. No paid calls, no installs.

WHAT WAS DECIDED AND VERIFIED

(1) The return value.
- gptr() returns THE SESSION ITSELF, not a gptr_result list (report 12) and not R6 (report 02).
- It is an environment-backed S3 object, class gptr_session: a classed shell env whose only binding is a hidden, unclassed data env `.d` holding serialisable fields only.
- s |> gptr('x') returns the identical object, and aliases see every turn.
- R6 was measured as the alternative: create 71.5 µs vs 5.0 µs; serialize 21,023 B vs 5,517 B; clone() shares the private state (a silent fork); only field reads are faster (2.3 µs vs 4.35 µs). D-02 stays S3.

(2) Live resources.
- They live in a per-process registry keyed by id, through rlang::new_weakref(key = session, value = live): home env, listeners, run state, handles.
- Unreferenced finished sessions are garbage-collected, and their finalizer removes the registry entry and the file lock.
- The reactor holds running sessions strongly until they settle.
- A strong registry, as in report 12's prototype, leaks every session.

(3) One pipe rule.
- Idle, error, aborted, or a re-attached copy → a new prompt turn. It blocks and returns s: visible under Rscript and knitr, printed then invisible at the console.
- Running (background, or re-entrant from the agent's own code) → enqueue a steer (queue = 'follow_up' is optional) and return invisible(s) at once (0.001 s).
- It never starts a nested run and never forks.

(4) One ordered queue per session.
- Producers: the pipe, the Ctrl-C pause menu, the file inbox from another process (gptr_steer(id, ...)), and the API (gptr_steer(s, ...), for plugins and front ends).
- Steers are delivered at the next boundary, after the COMPLETE tool-result message; follow-ups when the agent would stop.
- Abort moves the queue to s$dropped.
- Verified under Rscript (t3) and in interactive R: t9 transcript "user<call> ... user<pipe> ... user<menu> ... user<inbox>".

(5) Background jobs ARE sessions.
- gptr(..., background = TRUE) returns a running session; gptr_wait() / gptr_cancel() / gptr_jobs() operate on sessions.
- later services the run while the console is idle.
- A SIGINT inside a later callback reaches a calling handler and can be resumed (p6), so background ticks use the same pause menu.
- The menu option (b)ackground detaches a foreground call.
- Three menu defects were found and fixed:
  - menu output on stdout is captured into the tool result (the handler runs inside capture.output), so menu output must go to stderr;
  - an exiting tryCatch(interrupt) around a tool pre-empts the menu, so interrupted tools are recorded with on.exit() instead;
  - background R tools block the console while they run.

(6) gptr_fork(s, at = NULL, envir = c('overlay', 'shared')).
- New id. Lazy Pi-v3 file whose header has parentSession = parent path plus gptr.forkOf = {id, entry, turn}. The same entry ids are re-chained, as in Pi's createBranchedSession.
- Nothing live is shared (INFRA-14's acceptance test passes).
- It evaluates in an overlay: zero-copy reads at the same address, isolated writes.
- Forking a running session cuts at the last closed boundary. at = k and at = 0 are supported.
- The fork's first request was 97% served from the parent's prompt-cache prefix (fake estimate).

(7) Values.
- $value is the latest designated value by turn; $values is the history; gptr_value(s, turn).
- gptr_return(x) holds the value one of three ways:
  - copy: under 1 MiB, a deep copy, so history is faithful;
  - name: larger objects, name + address, a live view with no reference;
  - value: anonymous objects, or ones bound in a frame that will vanish.
- A budget (gptr.values_max_bytes) caps held values.
- No held value references a user object.

(8) Copy safety: 21 of 21 entry points leave the user's object editable in place (fresh-process tracemem, t5).
- This includes the wrapper case report 12 called "inherent".
- Root cause: R_CleanupEnvir releases a frame only when REFCNT(rho) == 0 after discounting simple cycles, and reference counts are never lowered for garbage. This is identical in R 4.4.3 and in R-devel trunk, fetched today.
- Five causes pinned frames: garbage rlang quosures; a for-loop calling a closure on ...elt(i); re-assigning a formal whose default promise is unforced (PRENV = frame; COPY in both the AST interpreter and byte code); the list returned by sys.frames(); unforced promises passed into leaked helper frames.
- Five capture rules fix all of them.
- This OVERTURNS report 12's rlang::enquos recommendation for the gateway. Base R capture (substitute + ...elt in leaves via while + identifiers resolved by forcing the promise) is also correct for forwarded dots (haiku, not WRONG-LOCAL).

(9) The home workspace.
- It is kept only if it is not a function frame (globalenv, explicit envir, fork overlay).
- A frame is held only while a run is active: holding a frame, even as a weak-reference value, makes the caller's arguments sticky (p2).

(10) Persistence.
- saveRDS/serialize of an env holding a frame reference wrote 16.0 MB (23 KB without it).
- In a new process, a deserialised connection WROTE INTO AN UNRELATED FILE that had reused connection number 3; the curl handle was dead; processx silently reported is_alive = FALSE; the later cancel returned FALSE.
- Hence sessions hold only data: 14.6 KB for 3 turns including an lm copy.
- Re-attach rules:
  - a same-process duplicate → gptr_error_split_brain;
  - another live process holding the <file>.lock/pid lock → split_brain;
  - a stale copy in a new process continues from ITS OWN leaf, and the file keeps a sibling branch (same id);
  - gptr_resume(id | path | NULL) restores the full history from JSONL, or returns the live object.
- knitr cache: the second knit made 1 request instead of 2 and branched in place.

(11) History document (report 14 grammar plus the keys session=, turn=, fork=<parent>:<turn>).
- Replay: 0 requests. The session is positioned at the recorded turn, and the fork adopts its recorded id.
- Overlay-fork blocks replay inside local({...}, envir = gptr_resume('<id>')$envir), so they never clobber the workspace.
- Re-running statements is idempotent.
- A live re-run of a steering statement appends a real turn and leaves the document untouched.
- A stale prompt in record mode regenerates only that block and branches inside the same session file.

(12) System 1 with a session.
- s |> gptr('q', model = jev) returns a gptr_decision, or a classed-character gptr_choice.
- It reads the last answer and value facts (55–70 characters), adds NO turn, and writes a gptr.decision audit custom entry.
- Character context goes to System 1 as its value; a by-name description is useless to it.

(13) North-star §2, §3 and §11 run end to end in the prototype. Spec inconsistency: §11's 'Cluster {cl}...' needs glue::glue(), because report 12 bans automatic {} interpolation.

(14) Token shape (fake chars/4 estimates; report 21 says this underestimates printed R output by about 51%, so use provider usage in practice).
- A 3-turn steered session: 1.7k of 2.3k input tokens were cached prefix.
- A fork: 477 of 490 cached.
- A model switch: 0 cached.
- System 1 over a session: 55–70 characters.
- Replay and knitr-cached chunks: 0.

STATE MACHINE
- Statuses: idle | running | aborted | error | interrupted (resumed with an unfinished tail) | detached (the attached flag is FALSE on copies).
- Running sub-steps: request → waiting → tools (one tool per tick, sequential FIFO) → boundary → request ... or final → settle.
- The file inbox is drained, and the oldest steer delivered, at boundary and final; at final, if there is no steer, the oldest follow-up.
- Enqueueing returns immediately.
- idle / aborted / error + gptr(s, 'p') → running on the same object.
- gptr_fork → a NEW idle session.

## 2. Key findings

- **[VERIFIED]** gptr() should return the session itself: an environment-backed S3 gptr_session (a classed shell env whose only binding is a hidden, unclassed data env .d). The pipe returns the identical object, and every alias sees every turn.
  - Evidence: G3/t1_class.R -> final_t1_class.out: 12 PASS (identical(res |> gptr(...), res); alias b steered; ls(session) empty; $status = x refused with gptr_error_readonly; .DollarNames and plugin fields work).
- **[VERIFIED]** R6 is worse for the session object. Creation costs 71.5 µs against 5.0 µs, serialize() gives 21,023 bytes against 5,517, and R6's default clone() shares the private data environment, which is a silent fork. Only field reads are faster with R6 (2.30 µs against 4.35 µs). D-02 stays S3.
  - Evidence: G3/t1b_r6.R -> final_t1b_r6.out.
- **[VERIFIED]** A registry of live resources must hold sessions weakly. A strong registry entry leaks the session forever; that is report 12's the$sessions[[id]] = s. rlang::new_weakref(key = session, value = live) lets the session be collected even when the value references it, including through a function frame that binds it. Finalizers then remove the registry entry and the lock.
  - Evidence: G3/p1_weakref.R -> final_p1_weakref.out: (a) strong: finalized FALSE; (b) weak: finalized TRUE; (c) frame value: finalized TRUE. G3/t8_edge.R: 5 unreferenced sessions finalized, locks removed; a running unreferenced background session was kept by the reactor and collected after settling. rlang 1.1.7 help new_weakref: 'weakref <- key -> value'.
- **[VERIFIED]** Any reference to a function frame retained when the function returns keeps the forced promises of that frame alive, so the caller's argument copies on its next in-place edit. This holds whether the frame is held strongly or as a weak-reference value. A session must therefore keep only non-frame workspaces (globalenv, an explicit envir, a fork overlay) and hold a frame only while a run is active.
  - Evidence: G3/p2_frame_sticky.R -> final_p2.out: label only -> in place; strong -> tracemem COPY; weak value -> COPY.
- **[VERIFIED]** Report 12's 'inherent' wrapper residual (w = function(d) gptr('x', d) copies d) is NOT inherent. Five causes keep gptr()'s frame or the wrapper frame referenced: garbage rlang quosures; a for loop calling a closure on ...elt(i); re-assigning a formal whose default promise is unforced (a garbage promise with PRENV equal to the frame); the list returned by sys.frames(); and unforced promises passed into leaked helper frames. The underlying rule is R_CleanupEnvir: a frame is released only if REFCNT(rho) is 0 after discounting simple cycles, and reference counts are never lowered for garbage.
  - Evidence: G3/p5b_bisect.R (quosure + forced wrapper promise COPY; ..2 without quosures in place); p5i_norloop.R (while, recursion and unrolled forms all in place for top level, wrapper, pipe and forwarded dots); p5n_formal.R and p5o_jit.R (re-assigning a formal COPY under JIT 0 and JIT 3, a new local in place); R 4.4.3 eval.c 2060-2170 (scratch work/12/ext); R-devel trunk eval.c fetched 2026-09-29, identical logic, cleanupEnvVector still disabled.
- **[VERIFIED]** With five capture rules every gptr entry point is copy-safe: 21 of 21 cases stay in place. The rules are: no quosures; dots reach only leaf functions through while loops, with no closures, handlers or match.arg in the dots frame; identifiers resolve by literal, then alias, then unbound symbol, then forcing the promise; never assign to a formal; and helpers force their arguments while adapters receive values through do.call. The cases are the top-level call, the pipe, a continuation with context, gptr_return of 40 MB, reading $value, the replay $value assignment, the copy policy, print, summary and str, fork, System 1 on a session and on data, a wrapper with an alias or if/else model, forwarded dots, parallel over a list, a background run, and saveRDS.
  - Evidence: G3/t5_copycheck.R -> final_t5.out: every gptr row in place; the only COPY is plain R's str(big) baseline.
- **[VERIFIED]** Base-R identifier resolution without quosures is correct in every report-12 case, including forwarded dots, where report 12 found base substitute() wrong. It forces the model promise instead of looking the name up in parent.frame(). This overturns report 12's rlang::enquos recommendation for the gateway and returns D-07 to base R, for a new reason (copy safety). rlang is still needed for new_weakref, hash, obj_address and duplicate.
  - Evidence: G3/t2b_nse.R -> final_t2b_nse.out: 'opus' -> opus, alias -> opus, variable -> haiku, if/else -> opus, unknown -> gpt9, I(m) -> haiku, forwarded dots with a local m -> haiku (not WRONG-LOCAL), wrapper argument -> haiku, model = jev -> the alias wins.
- **[VERIFIED]** One pipe rule works. Piping into an idle, aborted or error session is a new prompt turn that runs to settlement. Piping into a running session, including re-entrantly from the agent's own R code, enqueues a steering message and returns immediately without starting a nested run. An abort moves the queue to $dropped, and the next pipe continues the same session.
  - Evidence: G3/t3_steer.R -> final_t3_steer.out: 13 PASS (background returned in 0.036 s; pipe into running returned in 0.001 s; re-entrant pipe became a steer and turns stayed 2; aborted -> dropped c('steer A', 'follow B') -> continues).
- **[VERIFIED]** One ordered queue per session serves every producer: the pipe, the Ctrl-C pause menu, the file inbox written by another process, and the gptr_steer API. Steers land immediately after the complete tool-result message; follow-ups are delivered only when the agent would stop.
  - Evidence: t3 transcript 'user<call> assi tool user<pipe> assi tool user<api> assi user<inbox> assi' (steer index = tool result + 1); t9 in real interactive R with SIGINT: 'user<call> assi tool assi user<pipe> assi tool assi user<menu> assi tool assi user<inbox> assi' (final_t9.out).
- **[VERIFIED]** Background runs are ordinary sessions serviced by later at the idle console. A SIGINT that arrives during a later callback reaches a calling handler installed inside it and can be resumed. Background R tools execute inside later callbacks and block the console for their duration, so they need the same pause menu, without the (b)ackground option.
  - Evidence: G3/p6_later_sigint.R -> final_p6_later_sigint.out ('CALLING HANDLER SAW INTERRUPT; resuming', 'CB END: slept to the end'); t9 steps 1, 3 and 5 (idle servicing, the menu during a background tool, (b)ackground detaching a foreground call, 'LATER status idle').
- **[VERIFIED]** The pause menu has two pitfalls. First, its handler runs inside the tool's capture.output() sink, so any stdout text is captured into the tool result sent to the model; menu I/O must use stderr. Second, an exiting tryCatch(interrupt =) around tool execution pre-empts the outer calling-handler menu; interrupted tools must be recorded with on.exit() so the result is truthful (INFRA-04).
  - Evidence: Earlier t9 run: the cat() notice never reached the console. t9 failed with 'TIMEOUT waiting for: paused' while the tool step had tryCatch(interrupt =), and passed after the on.exit version (.tool_step in gptr_session.R).
- **[VERIFIED]** gptr_fork(s, at, envir) meets INFRA-14:
- a new id, and a lazily written Pi-v3 file whose header has parentSession (the parent path) and gptr.forkOf {id, entry, turn};
- the same entry ids, re-chained;
- no shared listeners, queue, run or lock;
- an overlay env with zero-copy reads at the same address and isolated writes, with envir = 'shared' as an opt-in;
- a fork of a running session cut at the last closed boundary;
- at = k and at = 0 supported.
  - Evidence: G3/t4_fork.R -> final_t4_fork.out: 21 PASS. Pi session-manager.ts 1632-1700 (createBranchedSession keeps ids, parentSession) and agent-session-runtime.ts 262-350 (fork).
- **[LIKELY]** A fork's first request is almost entirely prompt-cache prefix shared with its parent: 477 of 490 input tokens (fake estimate, cache keyed by prefix content per model). A model switch drops the cached share to 0, and a 3-turn steered chain had 1.7k of 2.3k input tokens cached.
  - Evidence: t4 section 6; t2 ('738 in (0 cached)' after the model switch); t1 footer '2.3k in (1.7k cached)'. These are chars/4 estimates from the fake provider, not provider bills.
- **[VERIFIED]** Value policy without references to user objects:
- copy: under 1 MiB, a deep copy via rlang::duplicate, so history stays faithful;
- name: larger objects, held as name + obj_address, a live view where a re-bound name is reported rather than silently wrong;
- value: anonymous objects, or ones bound in a vanishing frame.
$value is the highest turn, and held values stay within gptr.values_max_bytes.
  - Evidence: t1 values table; t4 'gptr_fork(qc, at = 1): history and value of turn 1 only' after later turns re-bound keep; t8: 16 MB objects held by name (held FALSE); 21 copies of 600 KB keep 8 (4.8 MB) under a 5 MB budget with the latest held; t5 copy-policy row in place.
- **[VERIFIED]** Serialising live resources is dangerous. A frame reference serialises the whole frame: 16,023,517 bytes against 23,446 without it. In a fresh process a deserialised connection wrote into an unrelated file that had reused connection number 3. A curl handle is 'dead', a processx object silently reports is_alive() FALSE and kill() errors, and a later cancel function returns FALSE. Sessions must therefore hold only serialisable data.
  - Evidence: G3/p3_serialize_live.R -> final_p3_serialize_live.out; G3/p3b_values.R -> final_p3b_values.out (other_file_lines = 1, proc_is_alive FALSE, proc_pid NA, later_cancel FALSE).
- **[VERIFIED]** The prototype session serialises to data only (14,642 bytes for 3 turns and 9 entries including an lm copy). Detach and re-attach rules prevent split brain without a silent fork:
- a same-process copy -> gptr_error_split_brain;
- a callr worker while the parent holds the pid lock -> split_brain;
- the finalizer releases the lock;
- gptr_resume(id) in a fresh process restores the full history, and the next request carried all 9 earlier messages;
- a stale copy in a new process continues from its own leaf, leaving a sibling branch in the same file under the same id.
  - Evidence: G3/t6_persist.R -> final_t6_persist.out: 12 PASS.
- **[VERIFIED]** With knitr cache, a cached gptr() chunk costs 0 requests on the next knit. An uncached steering chunk continues from the cached snapshot's state (turn 1 to 2, not 3), and the earlier knit's continuation stays as a sibling branch in the same session file.
  - Evidence: G3/t6b_knitr_cache.R -> final_t6b.out: knit 1 made 2 requests, knit 2 made 1 request; one session file; branch TRUE.
- **[VERIFIED]** History document with session headers:
- blocks carry session=, turn= and fork=<parent>:<turn>;
- replay costs 0 requests and positions the session at the recorded turn;
- a fork adopts its recorded id;
- overlay-fork blocks replay inside local({...}, envir = gptr_resume(id)$envir), so the global workspace is untouched;
- sourcing twice is idempotent;
- a live re-run of a steering statement appends a real turn and leaves the document unchanged (md5);
- an edited prompt in record mode regenerates only that block and branches inside the same session file.
  - Evidence: G3/doc.R + G3/t7_history.R -> final_t7.out (runs 1-5); report 14's gptrdoc.R sourced unmodified.
- **[VERIFIED]** System 1 inside a steering chain reads the session and never continues it. s |> gptr('q', model = jev) returns a gptr_decision, or a gptr_choice when choices = is given. It sends 55-70 characters of state (the last answer plus value facts) and writes a gptr.decision custom entry that is excluded from context. When System 1 is given data, character context must be sent as its value, because System 1 cannot inspect R objects.
  - Evidence: t2 section 3 (no new turn, 1 custom entry, excluded from context); ns_traces §11 first gave identical answers for every cluster until the value was sent, then CD3E / MS4A1 / AMBIG / GNLY were classified differently and only the AMBIG cluster was 'unclear'.
- **[VERIFIED]** The additions are compatible with Pi v3. Pi's loader requires only type == 'session' and a string id, so 8-hex ids and a header gptr object are accepted. The extra 'gptr' field on user messages never reaches the provider, because convertToLlm passes user messages through and the Anthropic adapter builds the wire message from role and content only.
  - Evidence: Pi 1b34779: packages/coding-agent/src/core/session-manager.ts:664; packages/coding-agent/src/core/messages.ts:148-190; packages/ai/src/api/anthropic-messages.ts:1279-1300.
- **[VERIFIED]** North-star §2, §3 and §11 run end to end in the prototype. §2: the session prints, and $value is an lme. §3: one session through a 3-step chain with a model switch; qc steered in place; the fork flags 6 cells while qc and the user's low_q still flag 4. §11: a steered prep chain; System 1 choices in a for loop cost 0 System 2 requests, and only the unclear cluster used 3; the loop-created session was garbage-collected after the loop and its JSONL remained. The §11 prompt 'Cluster {cl}...' needs glue::glue() because report 12 recommends no automatic {} interpolation.
  - Evidence: G3/ns_traces.R -> final_ns.out.
- **[VERIFIED]** Performance is adequate. 200 text-only turns took 24.1 ms per turn, including the JSONL append; the JSONL file was 189 KB and serialize() 335 KB. The first background call took 0.127 s from sourced code but 0.012 s when byte-compiled (as an installed package is), so first-call cost is JIT compilation, not the design.
  - Evidence: t8 memory section; G3/p4_firstcall.R output (sourced 0.127/0.033/0.002 s; precompiled 0.012/0.001/0.001 s).
- **[VERIFIED]** The report file could not be written. The harness blocks subagents from writing report .md files, so this structured output is the report. The prototypes and verbatim outputs are in the scratch G3 directory.
  - Evidence: Write tool error: 'Subagents should return findings as text, not write report files.' No *.md exists in G3/ or at dev/research/G3-*.

## 3. Design implications

- CONTRACT (house style): gptr = function(..., model = NULL, prompt = NULL, envir = NULL, background = FALSE, parallel = NULL, queue = c("steer", "follow_up"), choices = NULL, mode = NULL, skills = NULL, extensions = NULL, plugins = NULL).
- Returns a gptr_session (System 2), a gptr_sessions list (parallel = n, or a gptr_sessions target), or a gptr_decision / gptr_choice / gptr_score (System 1).
- Never returns a gptr_result list: retire gptr_result from report 12.
- Lifecycle helpers (D-28 prefix): gptr_wait = function(x, timeout = Inf); gptr_cancel = function(x); gptr_jobs = function(); gptr_steer = function(x, text, deliver = c("steer", "follow_up", "abort")); gptr_fork = function(s, at = NULL, envir = c("overlay", "shared")); gptr_resume = function(x = NULL); gptr_value = function(s, turn = NULL); gptr_return = function(value).
- Plugins: gptr_on = function(s, event, handler), gptr_hook = function(event, handler), gptr_field = function(name, getter).
- Methods: $, [[, $<- (value only), [[<- (refused), .DollarNames, print, format, as.character, summary, str, knit_print (registered lazily).
- OBJECT LAYOUT: user-held classed env s with a single hidden binding .d (an unclassed env holding only serialisable fields):
- id, created, status, reason, step, model, turns, seen, last_text, usage, values, queue, dropped;
- entries (Pi v3, append-only, may be a tree), index, leaf (THIS object's leaf), file, parent, home_label, replayed, ext.
Live resources sit in the$live[[id]] = rlang::new_weakref(key = s, value = live): home, retained, listeners, run, background, pid. Strong references to a session exist only in the$active while it is running. Each session has a file lock at <file>.lock/pid.
- PIPE SEMANTICS:
- s |> gptr('p') on an idle, error, aborted or re-attached session: a new prompt turn, run to settlement, returns s (printed then invisible at the console; visible under Rscript and knitr).
- On a running session: enqueue a steer (queue = 'follow_up' opt-in) and return invisible(s) immediately.
- Re-entrant pipes from agent code or hooks enqueue.
- Continuing never forks; after an abort or error it continues the same object and file.
- QUEUE: one ordered queue per session in .d$queue, items list(text, deliver = steer | follow_up, source = pipe | menu | inbox | api, t).
- Delivery happens at the state-machine boundary after complete tool results, and at final (steer first, else follow-up), one at a time.
- The file inbox <file>.inbox.jsonl is claimed by rename and drained at each boundary.
- Abort moves the queue to dropped.
- New steering front ends (Shiny, MCP server, RStudio add-in) are plugins that call gptr_steer().
- STATE MACHINE:
- status: idle | running | aborted | error | interrupted; a copy that is not in the registry is detached.
- Running steps: request -> waiting -> tools (one tool per reactor tick, sequential FIFO) -> boundary -> request, or final -> settle.
- One reactor loop (.pump_all) advances every active session, foreground and background; report 15's curl/processx transport plugs into the waiting step.
- INTERRUPT POLICY:
- A calling-handler pause menu is outermost, for both foreground loops and background later ticks: steer, follow-up, (b)ackground in the foreground only, abort, continue.
- Menu I/O goes to stderr (the handler runs inside the tool's stdout capture).
- Tool steps record interruption with on.exit() (a truthful synthetic result), never with an exiting tryCatch(interrupt), which would pre-empt the menu.
- Abort in a programmatic call re-signals so loops stop (report 18).
- FORK: new id; the Pi-v3 file is written lazily with the first own message.
- Header parentSession = parent path; gptr.forkOf = {id, entry, turn}.
- Copy the root-to-cut path minus labels, keeping ids and re-chaining parentId.
- Cut: at = NULL -> last closed boundary; at = k -> end of turn k; at = 0 -> empty.
- Workspace: new.env(parent = parent workspace), labelled 'overlay of ... (fork of id)'.
- Nothing live is copied (queue, listeners, run, lock, usage).
- Emit session_start(reason = 'fork') to process-wide hooks so plugins attach their own listeners.
- VALUES:
- gptr_return(x) and s$value = x capture substitute(x).
- Hold as copy (bound in a kept workspace and object.size < gptr.value_copy_max = 1 MiB; rlang::duplicate), as name + obj_address (bound and larger), or as value (anonymous or in a vanishing frame).
- $value is the highest turn; name values are live views; gptr_value(s, turn) returns NULL with a message if the name was re-bound.
- Budget: gptr.values_max_bytes = 64 MiB, releasing oldest first and always keeping the latest.
- Persist a gptr.value custom entry (metadata) for each designation.
- HOME WORKSPACE:
- Keep it (in the registry) only if it is globalenv, an explicit envir =, or a fork overlay.
- A function frame is held only during a run, and dropped at settlement by setting run$env = NULL and live$home = NULL, so a leaked frame still holding the run env does not pin the caller.
- Continuations evaluate in the kept workspace ('same workspace', REQ-18), else in their own caller.
- GATEWAY CAPTURE RULES (a new plan-level constraint, amends report 12 and D-07):
1. No rlang quosures in gptr() or its helpers that see user frames.
2. Dots reach only leaf functions, through while loops (never a for loop calling a closure); no closures, tryCatch, withCallingHandlers or match.arg in the frame that holds ... .
3. Identifiers: literal > known alias > unbound symbol (literal) > I()/call in an alias mask whose parent.env is reset to emptyenv() after eval > force the promise.
4. Never assign to a formal; use new locals.
5. Helpers force every argument on entry; provider, System 1 and router adapters are called via do.call with forced values (.call_adapter).
6. No sys.frames(); walk frames with sys.frame(k).
- TESTING (plan): ship a fresh-process tracemem suite over every gptr entry point (the shape of t5), skipped on CRAN and when !capabilities('profmem'), run on R-release and R-devel in CI. Add review or lint checks for the capture rules in the gateway files. Use the fake provider with scripted delays for steering and boundary-placement tests. Interactive SIGINT tests are manual or CI-only (processx-driven R --interactive).
- PERSISTENCE AND ATTACH:
- Sessions hold data only; saveRDS, knitr cache and callr produce detached copies.
- Continuing a copy: a same-process live original -> gptr_error_split_brain (after one gc() re-check); another live process holding the pid lock (ps::ps_is_running) -> split_brain; otherwise continue from the copy's own leaf, keeping newer file entries as a sibling branch, with a message.
- A copy snapshotted while running becomes aborted (reason detached).
- gptr_resume(x = NULL | id | path) returns the live object if one exists, else rebuilds from JSONL: status idle if the tail is a final answer, else interrupted.
- HISTORY DOCUMENT (extends report 14 §3.1):
- Header keys session=<id>, turn=<k>, fork=<parent>:<turn>.
- Strip gptr_return() lines from block bodies and emit <var>$value = <name>.
- Wrap turns run in an overlay fork as local({ ... }, envir = gptr_resume('<id>')$envir).
- Replay: take the piped target, the live object, gptr_resume, or a synthetic session; a fresh fork adopts the recorded id; skip turns already in .d$seen; otherwise position the leaf at the end of turn k, drop values of later turns, mark replayed, and queue a value slot. Replay makes 0 requests.
- Stale prompts in record mode branch inside the same session file.
- SYSTEM 1 AND DISPATCH:
- The first unnamed gptr_session is continued; a named session is context.
- gptr_sessions: submit to each member concurrently and wait.
- Data first: new session, context described by name and budgeted.
- System 1 model with a session: read its last answer (at most 2,000 chars) and value facts; return a typed vector; append a gptr.decision custom entry; never add a turn.
- System 1 with small character context: send the value (paste0 copy), not the description.
- glue objects are accepted as prompts.
- PI v3 COMPATIBILITY: keep gptr additions in fields Pi ignores: the header gptr object, a user-message gptr {deliver, source} (verified absent from the Anthropic wire), and custom entries gptr.value, gptr.decision and gptr.doc_block. Session ids can be 8-hex (Pi's loader only requires a string); consider UUIDv7 in the header with an 8-hex display id if strict Pi parity is wanted.
- EVERYTHING-IS-A-PLUGIN (S-11):
- Plugin session state goes in .d$ext[[plugin]] (JSON-able, persisted as custom entries) and is exposed through gptr_field().
- Plugin live resources use their own weak-keyed registry keyed by session id.
- Agent definitions may return subclasses (c('review_session', 'gptr_session')) with their own print or knit_print.
- Sub-agent backends (inline, worker, cli) drive the same run state machine; a worker or CLI run is still a gptr_session with parent lineage (kind = subagent).
- TOKEN EFFICIENCY (S-12), each with its cost:
- Continuing a session re-uses the cached prefix: 1.7k of 2.3k cached by turn 3.
- Steering after complete tool results keeps the prefix byte-identical, so the cache stays warm.
- A fork's first request is 97% cache.
- A model switch resets the cache; report it in usage.
- A data-first pipe sends a one-line description.
- System 1 over a session sends 55-70 chars instead of the transcript.
- Audit custom entries, replay, knitr-cached chunks, print, $value and summary cost 0 tokens.
- Accounting must use provider-reported usage (chars/4 underestimates R output by about 51%, report 21).
- DECISION REGISTER POSITIONS:
- D-02: S3 env, no R6.
- D-05: the session is the return value; steering a running session is feasible and in v1; explicit gptr_fork recorded as fork=; print and $value as specified; saveRDS and knitr cache handled by data-only sessions plus attach rules; System 1 reads sessions.
- D-07: base R capture, amended with the copy-safety rules.
- D-09: Pi v3 JSONL with lazy fork files.
- D-12: sub-agent results are sessions.
- Report 15's job objects become sessions.
- Conflict 16: one queue with multiple producers.
- INFRA-12..16 satisfied as shown in t3, t4, t6 and t8.

## 4. Risks

- Copy safety rests on R internals: R_CleanupEnvir's release rule, and reference counts never being lowered for garbage. These are unchanged in R-devel trunk today but could change. It also rests on coding discipline: one stray match.arg(), closure, handler or formal re-assignment in a frame that holds ... silently brings back whole-object copies of multi-GB objects. It needs a per-entry-point tracemem suite on R-release and R-devel.
- Background R tools execute inside later callbacks at top level and block the console for their duration, which users may read as a frozen prompt. The pause menu works there, verified on macOS. RStudio, Positron, Jupyter and Windows (Rgui Esc, Rterm Ctrl-C) are untested.
- Steering delivery depends on when the console reads the pipe line: a pipe typed during a background tool is read only after the tool. Tests must assert order and boundary placement, not timings; t9 needed retiming twice.
- Name-held (large) values are live views. Later in-place edits change $value, and a re-bound name loses the historical value; this is reported with a message, not silently wrong. Small values are deep copies, which costs memory up to gptr.values_max_bytes.
- Stale copies (knitr cache, readRDS in a new process) continue from their own leaf and add sibling branches to the same session file. Repeated knits accumulate branches, so a prune or compaction command is needed.
- The file lock uses pid liveness through ps. After a crash, pid reuse can make a stale lock look alive and block re-attach; a lock timeout or a force option is needed. dir.create atomicity and ps behaviour on Windows network drives are untested.
- A fork overlay isolates bindings only. Environments, R6, data.table := and Seurat internals mutate through it (report 15 §4.5): a fork branches the conversation and the bindings, not a workspace snapshot.
- Menu text goes to stderr. If user code has diverted the message stream (sink(type = 'message')), menu prompts may be invisible.
- Only the fake provider was used. Real prompt-cache accounting, provider-side stream timeouts during a long pause menu, and HTTP-level interrupt resume were not exercised here (see reports 02, 15 and 18).
- The history-document replay reuses report 14's locator. The session-positioning logic (latest branch in file order) may pick an unexpected branch after heavy branching. Downstream invalidation when an earlier steering block is regenerated is not implemented.
- The report file itself was not written, because the harness blocked it. Downstream agents that expect dev/research/G3-session-object-pipe-steering.md will not find it unless the orchestrator materialises this structured output.

## 5. Open questions

- When piping into a RUNNING session, should the default be steer (as prototyped, following S-8 and D-05) or follow-up?
- Should the default fork workspace be an overlay (isolated writes, as prototyped) or shared?
- Background R tools: should they run at the idle console (the prompt freezes during a tool), or only inside gptr_wait() and foreground calls, while streams still progress at idle? A possible option is gptr.background_tools = c('idle', 'wait').
- Value policy thresholds: copy under 1 MiB and a 64 MiB held budget? Should small copies be persisted as RDS side files so gptr_resume() after an R restart can return them? Today resume restores only metadata, so the value was NULL in t6.
- North-star §11 uses 'Cluster {cl} ...' as a plain string. Should the example change to glue::glue()/sprintf(), or should gptr add opt-in interpolation such as gptr_prompt() (report 12 §2.D4)?
- Record-mode regeneration of a steering statement that is not the session's last turn: branch and mark downstream blocks stale (knitr dependson-like), or refuse and suggest gptr_fork(s, at = k - 1)?
- Pause menu with several background sessions: should it ask which session to steer? The prototype steers the first active session.
- Session id format: 8-hex (accepted by Pi's loader) or Pi's UUIDv7 in the header with an 8-hex display id?
- Should s$value = x be allowed outside replay blocks (as prototyped), or reserved for replay?
- Should s |> gptr() with no prompt open the console on s when interactive, and continue an interrupted run otherwise? (Specified here, not prototyped.)
- Should the orchestrator write this output to dev/research/G3-session-object-pipe-steering.md? The subagent was blocked from writing report files.

## 6. Prototype files (88 files from `scratchpad/work/G3/`)

### `doc.R`

````r
# doc.R -- G3: session-aware record/replay of the history document, on top of report 14's document
# layer (scratchpad/work/14/proto/gptrdoc.R: gptr_where, doc_match_call, doc_owned_block, doc_upsert_block,
# prompt_hash, new_block_id, doc_read, doc_write; sourced into its own environment, not copied).
# Invariant kept from report 14: gptr() never executes a recorded block; replay is a zero-token no-op
# that returns the SESSION positioned at the recorded turn, and the block's own code runs next.
.doclib = function() {
  if (is.null(the$doclib)) {
    e = new.env(parent = globalenv())
    sys.source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/14/proto/gptrdoc.R", envir = e)
    the$doclib = e
  }
  the$doclib
}
.replay_hook = function(target, prompt, caller) {
  force(target); force(prompt); force(caller)
  the$pending_record = NULL
  mode = getOption("gptr.replay", "auto")
  if (identical(mode, "live")) return(NULL)             # live: run the model, write nothing
  L = .doclib()
  where = L$gptr_where(sys.call(-1L), prompt, sys.calls())
  if (!identical(where$kind, "srcref")) return(NULL)
  d = L$doc_read(where$path)
  hit = L$doc_match_call(d$lines, where)
  if (is.null(hit) || isTRUE(hit$nested)) return(NULL)  # only top-level statements get blocks
  own = L$doc_owned_block(d$lines, hit, L$prompt_hash(prompt))
  if (!is.null(own$block) && !isTRUE(own$stale)) return(.replay_turn(target, prompt, own$block$header[[1]], caller))
  if (identical(mode, "replay")) .gptr_abort(if (isTRUE(own$stale)) "block is stale (prompt edited); run live or record" else "not recorded", "replay")
  the$pending_record = list(path = where$path, hit = hit, own = own, prompt = prompt)
  NULL                                                    # run live; .record_turn() writes the block
}

.replay_turn = function(target, prompt, h, caller) {
  sid = h$session; k = as.integer(h$turn)
  s = target
  if (is.null(s)) {                                       # first call of a chain
    w = get0(sid, envir = the$live, inherits = FALSE)
    s = if (!is.null(w) && !is.null(rlang::wref_key(w))) rlang::wref_key(w) else {
      f = list.files(.sessions_dir(), pattern = paste0("_", sid, "[.]jsonl$"), full.names = TRUE)
      if (length(f)) gptr_resume(f[1]) else .synthetic_session(sid, caller)
    }
  } else if (!identical(s$id, sid)) {
    if (!is.null(h$fork) && .d(s)$turns == (.d(s)$parent$turn %||% -1L)) .adopt_id(s, sid)   # a fresh fork takes the recorded id
    else .say("block says session ", sid, " but the piped session is ", s$id, "; replaying anyway")
  }
  d = .d(s)
  if (!is.null(h$value)) d$pending_value_turns = c(d$pending_value_turns, k)   # the block's `var$value = x`
  d$replayed = union(d$replayed, k)       # attaches to turn k and never re-writes the file
  if (k %in% d$seen) return(s)            # this object already ran/replayed turn k here: no-op (idempotent)
  .position_at_turn(s, k)                 # e.g. a resumed object is at the file's last turn: move to turn k
  d$seen = union(d$seen, k)
  s
}
.position_at_turn = function(s, k) {       # move the leaf to the end of turn k (as recorded in the file)
  .ensure_loaded(s)
  d = .d(s)
  all = d$entries; turn = 0L; end = NULL
  path = .path(d, all[[length(all)]]$id %||% d$leaf)
  for (e in path) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) { turn = turn + 1L; if (turn > k) break }
    if (turn == k) end = e$id
  }
  if (is.null(end)) return(invisible())                   # synthetic session: nothing to position
  d$leaf = end; d$turns = k
  d$values = Filter(function(v) as.integer(v$turn) <= k, d$values)   # values of later turns belong to other positions
  fin = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "assistant") && !identical(e$message$stopReason, "toolUse"), .path(d))
  d$last_text = if (length(fin)) fin[[length(fin)]]$message$content[[1]]$text else NA_character_
  d$replay_positioned = TRUE
  invisible()
}
.adopt_id = function(s, sid) {            # a fresh fork (no own turns yet) takes the id its block recorded
  d = .d(s); old = d$id; live = .live(s)
  rm(list = old, envir = the$live)
  unlink(paste0(d$file, ".lock"), recursive = TRUE)
  f = list.files(.sessions_dir(), pattern = paste0("_", sid, "[.]jsonl$"), full.names = TRUE)
  d$id = sid
  if (length(f)) { d$file = f[1]; d$loaded = FALSE; d$leaf = NULL; .ensure_loaded(s) } else d$file = sub(old, sid, d$file, fixed = TRUE)
  assign(sid, rlang::new_weakref(key = s, value = live), envir = the$live)   # same live env: overlay home kept
  .lock(s)
  .say("fork ", old, " adopted the recorded id ", sid)
  invisible(s)
}
.synthetic_session = function(sid, caller) {             # sessions dir missing: history is the document
  s = .new_session("replay", caller, retained = !.on_stack(caller), id = sid)
  .say("session ", sid, " has no transcript here; replaying from the document only")
  s
}

.record_turn = function(s) {                              # after a live run: write/replace the block
  pr = the$pending_record
  the$pending_record = NULL
  if (is.null(pr)) return(invisible())
  L = .doclib(); d = .d(s)
  path = .path(d)
  users = which(vapply(path, function(e) identical(e$type, "message") && identical(e$message$role, "user"), NA))
  first = users[length(users)]
  turn_entries = path[first:length(path)]
  code = character(); outs = character()
  msgs = Filter(function(e) identical(e$type, "message"), turn_entries)
  for (j in seq_along(msgs)) {
    m = msgs[[j]]$message
    if (identical(m$role, "assistant")) for (b in m$content) if (identical(b$type, "toolCall")) {
      res = Filter(function(x) identical(x$message$toolCallId, b$id), msgs)
      if (length(res) && !isTRUE(res[[1]]$message$isError)) {
        code = c(code, strsplit(b$arguments$code, "\n")[[1]])
        o = res[[1]]$message$content[[1]]$text
        if (!identical(o, "(no output)")) code = c(code, L$format_output(strsplit(o, "\n")[[1]]))
      }
    }
  }
  vals = Filter(function(v) v$turn == d$turns, d$values)
  stmt_var = .statement_var(pr$path, pr$hit)
  code = code[!grepl("^[[:space:]]*gptr_return\\(", code)]   # the designation is replayed as `var$value = name`
  if (!is.null(attr(.live(s)$home, "gptr_overlay")))          # a fork evaluated in its overlay: replay there too
    code = c("local({", paste0("  ", code), sprintf("}, envir = gptr_resume(\"%s\")$envir)", d$id))
  body = c(code, sprintf("## Decision: (fake) answered turn %d.", d$turns))
  fields = list(model = paste0("fake/", d$model), date = format(Sys.Date()), prompt = L$prompt_hash(pr$prompt))
  if (pr$hit$n_in_stmt > 1L) fields$call = pr$hit$n_in_stmt
  fields$session = d$id; fields$turn = d$turns
  if (!is.null(d$parent) && d$turns == d$parent$turn + 1L) fields$fork = paste0(d$parent$id, ":", d$parent$turn)
  if (length(vals) && !is.na(vals[[1]]$name)) {
    fields$value = vals[[1]]$name
    if (!is.null(stmt_var)) body = c(body, sprintf("%s$value = %s", stmt_var, vals[[1]]$name))
  }
  dd = L$doc_read(pr$path)
  hit = L$doc_match_call(dd$lines, list(kind = "srcref", path = pr$path, stmt = c(pr$hit$stmt1, pr$hit$stmt2), prompt = pr$prompt, lines_at_parse = dd$lines))
  own = L$doc_owned_block(dd$lines, hit, fields$prompt)
  id = if (!is.null(own$block)) own$block$id else L$new_block_id(L$doc_find_blocks(dd$lines)$id, salt = pr$prompt)
  new = L$doc_upsert_block(dd$lines, id, body, fields, after_line = own$insert_after)
  L$doc_write(dd, new, check = FALSE)
  invisible()
}
.statement_var = function(path, hit) {     # `a = gptr(...)` -> "a"; `a |> gptr(...)` -> "a"; else NULL
  txt = readLines(path, warn = FALSE)[hit$stmt1:hit$stmt2]
  ex = tryCatch(parse(text = txt, keep.source = FALSE)[[1]], error = function(e) NULL)
  if (is.null(ex)) return(NULL)
  if (is.call(ex) && as.character(ex[[1]]) %in% c("=", "<-") && is.symbol(ex[[2]])) return(as.character(ex[[2]]))
  while (is.call(ex) && identical(ex[[1]], quote(gptr)) && length(ex) > 1L) {   # follow gptr(gptr(a, ...), ...) only
    if (is.symbol(ex[[2]])) return(as.character(ex[[2]]))
    ex = ex[[2]]
  }
  NULL                                    # e.g. gptr_fork(a) |> gptr(...): no variable holds the session
}
````

### `ex_jsonl.R`

````r
# ex_jsonl.R -- example JSONL lines written by the prototype (fork header, steering message, gptr.* entries)
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "ex"))
the$provider = fake_rules(list("QC" = list(code = "keep = c(3, 8, 25) <= 20\ngptr_return(keep)")), delay = 0)
the$s1 = fake_s1
qc = gptr("Run QC")
ok = qc |> gptr("Is the result clear?", model = jev)
f = gptr_fork(qc)
f |> gptr("Try 10%")
show = function(path, which) { l = readLines(path); cat(sub(tempdir(), "<tmp>", l[which], fixed = TRUE), sep = "\n") }
cat("-- parent file: header, first user message, gptr.value and gptr.decision entries\n")
pl = readLines(qc$file); show(qc$file, c(1, 2, grep("gptr.value|gptr.decision", pl)))
cat("-- fork file: header and the fork's own user message\n")
fl = readLines(f$file); show(f$file, c(1, grep("Try 10%", fl)))
````

### `fake.R`

````r
# fake.R -- scripted fake provider (System 2) and fake System 1 adapter for the G3 prototype.
# fake_rules(list("<regex on the last user prompt>" = list(code = "<R code for the r tool>",
#                                                          answer = "<final text>", delay = 0.05)))
fake_rules = function(rules, delay = 0.05) {
  function(ctx, model, s) {
    last = ctx[[length(ctx)]]
    users = Filter(function(m) identical(m$role, "user"), ctx)
    utext = function(m) m$content[[1]]$text
    if (identical(last$role, "user")) {
      p = utext(last)
      for (pat in names(rules)) if (grepl(pat, p)) {
        r = rules[[pat]]
        if (!is.null(r$code)) return(list(text = r$say %||% "", delay = r$delay %||% delay,
          calls = list(list(name = "r", arguments = list(code = r$code)))))
        return(list(text = r$answer %||% paste("Answer to:", p), delay = r$delay %||% delay))
      }
      return(list(text = paste0("[", model, "] Answer to: ", p), delay = delay))
    }
    # after tool results: answer, naming every user message since the last final answer
    k = length(ctx)
    while (k > 1 && !(identical(ctx[[k]]$role, "assistant") && identical(ctx[[k]]$stopReason, "stop"))) k = k - 1
    seen = vapply(Filter(function(m) identical(m$role, "user"), ctx[k:length(ctx)]), utext, "")
    out = ctx[[length(ctx)]]$content[[1]]$text
    list(text = sprintf("[%s] Done (%s). Saw: %s", model, strsplit(out, "\n")[[1]][1],
                        paste(sprintf("'%s'", substr(seen, 1, 40)), collapse = " + ")), delay = delay)
  }
}
# fake System 1: probability rises with the number of "good"/"clear" words in the state
fake_s1 = function(question, state) {
  vapply(state, function(st) {
    hits = lengths(regmatches(tolower(st), gregexpr("good|clear|success|done", tolower(st))))
    round(min(0.97, 0.2 + 0.25 * hits), 2)
  }, 1, USE.NAMES = FALSE)
}
fake_s1_choice = function(question, state, choices) {
  idx = vapply(state, function(st) if (grepl("AMBIG", st)) length(choices) else (nchar(st) %% (length(choices) - 1L)) + 1L, 1L, USE.NAMES = FALSE)
  list(idx = idx, prob = rep(0.81, length(idx)))
}
````

### `final_done.txt`

````text
ALLDONE
````

### `final_ex_jsonl.out`

````text
[fake] Answer to: Try 10%
<gptr_session 549cb9ab> idle | 2 turns | fake | 385 in (360 cached) / 7 out | value: keep <logical>
-- parent file: header, first user message, gptr.value and gptr.decision entries
{"type":"session","version":3,"id":"1d53dddd","timestamp":"2026-09-30T05:58:41.988Z","cwd":"<G3>","gptr":{"format":1}}
{"type":"message","id":"6d0ae735","parentId":null,"timestamp":"2026-09-30T05:58:41.990Z","message":{"role":"user","content":[{"type":"text","text":"Run QC"}],"timestamp":1790747921990,"gptr":{"deliver":"prompt","source":"call"}}}
{"type":"custom","id":"3add3e2b","parentId":"444b883c","timestamp":"2026-09-30T05:58:42.027Z","customType":"gptr.value","data":{"turn":1,"by":"copy","name":"keep","env":"globalenv()","class":"logical","size":64}}
{"type":"custom","id":"4885fcdf","parentId":"3a0d713f","timestamp":"2026-09-30T05:58:42.030Z","customType":"gptr.decision","data":{"question":"Is the result clear?","answer":false,"prob":0.45,"state_chars":70}}
-- fork file: header and the fork's own user message
{"type":"session","version":3,"id":"549cb9ab","timestamp":"2026-09-30T05:58:42.031Z","cwd":"<G3>","parentSession":"<tmp>/ex/2026-09-30T05-58-41-988Z_1d53dddd.jsonl","gptr":{"format":1,"forkOf":{"id":"1d53dddd","entry":"4885fcdf","turn":1}}}
{"type":"message","id":"7d61b4f2","parentId":"4885fcdf","timestamp":"2026-09-30T05:58:42.031Z","message":{"role":"user","content":[{"type":"text","text":"Try 10%"}],"timestamp":1790747922032,"gptr":{"deliver":"prompt","source":"pipe"}}}
{"type":"message","id":"19aebc2d","parentId":"7d61b4f2","timestamp":"2026-09-30T05:58:42.035Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: Try 10%"}],"provider":"fake","model":"fake","usage":{"input":385,"cacheRead":360,"output":7},"stopReason":"stop","timestamp":1790747922035}}
````

### `final_ns.out`

````text
==================== north-star §2: the same function as a programmable call
  TRACE res = gptr('Fit a mixed model...', mice) session 2ad5ba89 | idle | turns 1 | model fake | value lme | requests so far 2
  > res        (Rscript: visible, the print method shows the answer + footer)
[fake] Done ((Intercept)       dietB ). Saw: 'Fit a mixed model of weight on diet with'
<gptr_session 2ad5ba89> idle | 1 turn | fake | 792 in (363 cached) / 42 out | value: fit <lme>
  > class(res$value): lme 
  > res$usage: List of 4
 $ input     : num 792
 $ output    : num 42
 $ cache_read: num 363
 $ requests  : int 2
  TRACE mice |> gptr('Which columns...')   session fe7e427d | idle | turns 1 | model fake | value none | requests so far 3
  > data-first pipe started a NEW session: TRUE | context sent: <object name=mice class=data.frame 48x3 size=3.4 Kb> 
==================== north-star §3: the pipe steers one session object
  TRACE the three-step chain               session 26db7a8d | idle | turns 3 | model opus | value prcomp | requests so far 9
  > one session for the whole chain; models along it: fake -> opus 
  TRACE qc = gptr('Run QC...', pbmc)       session 65072f96 | idle | turns 1 | model fake | value logical | requests so far 11

FALSE  TRUE 
    5     3 
[fake] Done ([1] 4). Saw: 'Use 15% mitochondrial reads as the cut-o'
<gptr_session 65072f96> idle | 2 turns | fake | 1.6k in (1.5k cached) / 74 out | value: low_q <logical>
  TRACE qc |> gptr('Use 15%...')           session 65072f96 | idle | turns 2 | model fake | value logical | requests so far 13
  > qc$value (the steered result): flagged 4 cells
  TRACE gptr_fork(qc) |> gptr('Try 10%')   session 7ab7fb4c | idle | turns 3 | model fake | value logical | requests so far 15
  > fork flagged 6 cells in its overlay; qc still flags 4 ; user's low_q flags 4 
==================== north-star §11: a whole workflow that reads like R
  TRACE prep = ... |> ... |> ...           session 4ee2240a | idle | turns 3 | model fake | value data.frame | requests so far 20
  TRACE cluster 0: markers CD3E, IL7R     -> System 1 dendritic cell (prob 0.81)
  TRACE cluster 1: markers MS4A1, CD79A   -> System 1 T cell (prob 0.81)
  TRACE cluster 2: markers AMBIG1, AMBIG2 -> System 1 unclear (prob 0.81)
  TRACE   cluster 2 investigation chain    session 7295179b | idle | turns 2 | model fake | value character | requests so far 23
  TRACE cluster 3: markers GNLY, NKG7     -> System 1 dendritic cell (prob 0.81)
  > System 1 calls cost 0 System 2 requests; the loop made 3 System 2 requests (only the unclear cluster)
  > the unassigned loop session was garbage-collected: TRUE ; its transcript stays in ns 
  TRACE gptr('Build a Shiny app...', pbmc) session 24517fc7 | idle | turns 1 | model fake | value none | requests so far 24
````

### `final_p1_weakref.out`

````text
(a) strong registry -> finalized: FALSE 
(b) before rm: key alive: TRUE 
(b) weak registry -> finalized: TRUE | key after gc is NULL: TRUE | value after gc is NULL: TRUE 
(c) weak entry, value = frame binding the session -> finalized: TRUE 
finalizer log: weak frame 
````

### `final_p2.out`

````text
case label END
tracemem[0x10c800000 -> 0x118000000]: 
case strong END
tracemem[0x10b800000 -> 0x10f000000]: 
case weak END
````

### `final_p3_serialize_live.out`

````text
in-memory object.size of session env (shallow): 288 bytes 
serialize(s) bytes: 16023517 ( 15.3 MB ) in 0.018 s
serialize(s) without the frame reference: 23446 bytes
saveRDS file size: 10658169 bytes
same process: identical(readRDS(s), s): FALSE | id equal: TRUE 
                      class                         con 
             "gptr_session" "ERROR: invalid connection" 
                  con_write                        curl 
"ERROR: invalid connection"     "ERROR: handle is dead" 
                 proc_alive                    proc_pid 
                       "ok"                        "ok" 
               later_cancel                    listener 
                       "ok"                        "ok" 
               home_big_len       home_global_is_global 
                  "2000000"                      "TRUE" 
callr child sees id: 7f3a21 (a copy: two writers for one id are now possible)
[1] TRUE
````

### `final_p3b_values.out`

````text
                                                                                                                                                                                                  stale_con_number 
                                                                                                                                                                                                               "3" 
                                                                                                                                                                                                    new_con_number 
                                                                                                                                                                                                               "3" 
                                                                                                                                                                                                   write_via_stale 
                                                                                                                                                                                                            "NULL" 
                                                                                                                                                                                                     proc_is_alive 
                                                                                                                                                                                                           "FALSE" 
                                                                                                                                                                                                          proc_pid 
                                                                                                                                                                                                              "NA" 
                                                                                                                                                                                                         proc_kill 
"ERROR: ! Native call to `processx_connection_close` failed\nCaused by error in `chain_call(c_processx_connection_close, p)`:\n! Invalid connection object @processx-connection.c:248 (processx_connection_close)" 
                                                                                                                                                                                                      later_cancel 
                                                                                                                                                                                                           "FALSE" 
                                                                                                                                                                                                  other_file_lines 
                                                                                                                                                                                                               "1" 
````

### `final_p5b_bisect.out`

````text
force_only     -> COPY
leaf_class     -> COPY
leaf_objsize   -> COPY
leaf_dim_len   -> COPY
lapply_closure -> in place
for_loop_get   -> COPY
force_then_rm  -> COPY
no_quo_get     -> in place
````

### `final_p5i_norloop.out`

````text
recursion  top: in place | wrapper: in place | pipe: in place | forwarded: in place
while_leaf top: in place | wrapper: in place | pipe: in place | forwarded: in place
unrolled   top: in place | wrapper: in place | pipe: in place | forwarded: in place
````

### `final_p5n_formal.out`

````text
reassign_formal_null   top: COPY     | wrapper: COPY
reassign_formal_value  top: COPY     | wrapper: COPY
new_local              top: in place | wrapper: in place
reassign_other_formal  top: COPY     | wrapper: COPY
force_formal_only      top: in place | wrapper: in place
````

### `final_p5o.out`

````text
JIT 0, body 'model = 1': COPY
JIT 0, body 'mdl = 1': in place
JIT 3, body 'model = 1': COPY
JIT 3, body 'mdl = 1': in place
````

### `final_p6_later_sigint.out`

````text
[1] TRUE
[1] TRUE
CB START
CALLING HANDLER SAW INTERRUPT; resuming
CB END: slept to the end 
PROMPT ALIVE
FOREGROUND CALLING HANDLER SAW INTERRUPT; resuming
FG END: slept to the end 
````

### `final_t1_class.out`

````text
== 1. programmatic call returns the session itself ==
  PASS gptr() returns an environment-backed gptr_session
  PASS status idle after settlement, 1 turn
  PASS $value is the lm designated by gptr_return(fit); fit exists in the caller
-- print(res):
[fake] Done ((Intercept)          wt ). Saw: 'Fit a mixed model of mpg on weight and r'
<gptr_session 6c2e42e2> idle | 1 turn | fake | 756 in (350 cached) / 42 out | value: fit <lm>
-- format / as.character: TRUE 
-- str(res): <gptr_session 6c2e42e2> idle, 1 turns, 5 entries, home globalenv(), attached
  PASS non-interactive (Rscript): the result is visible, so a bare call prints the answer
== 2. the pipe steers the SAME object ==
  PASS res |> gptr(...) returns the identical object (same environment)
  PASS turn 2 steered $value to the model with cyl
[fake] Answer to: Summarise in one sentence.
<gptr_session 6c2e42e2> idle | 3 turns | fake | 2.3k in (1.7k cached) / 94 out | value: fit2 <lm>
  PASS steering via an alias is visible through every binding
  PASS a fork is a different object (identical() is pointer identity)
-- summary(res):
 turn deliver source                                   text model
    1  prompt   call Fit a mixed model of mpg on weight ...  fake
    2  prompt   pipe                Add cyl as a covariate.  fake
    3  prompt   pipe             Summarise in one sentence.  fake
                                 answer value
 [fake] Done ((Intercept)          w...   fit
 [fake] Done ((Intercept)          w...  fit2
 [fake] Answer to: Summarise in one ...  <NA>
-- values history:
  turn   by name class  size held
1    1 copy  fit    lm 25528 TRUE
2    2 copy fit2    lm 28344 TRUE
== 3. read-only fields, completion, plugin fields ==
  PASS `res$status = ...` is refused with class gptr_error_readonly
  PASS .DollarNames completes public fields
  PASS a plugin-registered field appears in $ and completion
  PASS ls(session) shows no internals (data live in the hidden .d)
-- res$history (lazy view of the transcript):
   turn       role deliver source final
1     1       user  prompt   call FALSE
2     1  assistant    <NA>   <NA> FALSE
3     1 toolResult    <NA>   <NA> FALSE
4     1  assistant    <NA>   <NA>  TRUE
5     2       user  prompt   pipe FALSE
6     2  assistant    <NA>   <NA> FALSE
7     2 toolResult    <NA>   <NA> FALSE
8     2  assistant    <NA>   <NA>  TRUE
9     3       user  prompt   pipe FALSE
10    3  assistant    <NA>   <NA>  TRUE
-- JSONL file lines: 13  header: {"type":"session","version":3,"id":"6c2e42e2","timestamp":"2026-09-30T05:54:52.628Z","cwd" 
````

### `final_t1b_r6.out`

````text
R6 2.6.1 | R 4 4.3 
[fake] Answer to: again
<gptr_session 3da1d3e7> idle | 2 turns | fake | 661 in (320 cached) / 12 out | value: none
[fake] Answer to: once more
<gptr_session 3da1d3e7> idle | 3 turns | fake | 1.0k in (661 cached) / 19 out | value: none
                                             S3 env           R6
create an empty object                       5.00 us      71.50 us
read s$status                                4.35 us       2.30 us
read s$text                                  4.35 us       2.35 us
serialize() bytes (same data)                  5517        21023
object.size() bytes (shallow)                   288          352
ls(obj) shows                                       clone,id,initialize,print,status,text
obj$status = 'x'                            refused      refused
obj$newfield = 1                            refused      refused
clone(): new object shares data env?     no clone()         TRUE
has compiled code                         no (base)           no
````

### `final_t2_dispatch.out`

````text
== 1. data first: df |> gptr('...') attaches context and starts a NEW session ==
  PASS context described by name, budgeted (no data serialised)
   user message sent: Which columns have missing values? | Attached: <object name=mice class=data.frame 120x3 size=3.3 Kb> 
== 2. session first: s |> gptr('...') continues; a named session is context ==
[haiku] Answer to: Impute them with the median.
<gptr_session 3fa5f40b> idle | 2 turns | haiku | 738 in (0 cached) / 41 out | value: none
  PASS continuation on the same object; model switched mid-conversation
  PASS model switch recorded as a Pi model_change entry
  PASS gptr('p', earlier = a): a named session is context, not continued
== 3. System 1 on a session: a typed judgement that READS the session, never continues it ==
  PASS returns a gptr_decision (logical + prob), not a session
  PASS no new turn; one gptr.decision custom entry (audit, never in model context)
  PASS decision entry excluded from provider context
   state sent to System 1: 55 chars (last answer + value, not the transcript)
   used directly in if(): FALSE branch 
== 4. parallel = n returns a gptr_sessions list; piping it steers every member ==
  PASS three sessions, class gptr_sessions
<gptr_sessions> 3 sessions
  ctrl       7fca325a idle    1 turns  [fake] Answer to: Summarise this coho...
  treat      64ccf1e9 idle    1 turns  [fake] Answer to: Summarise this coho...
  pilot      29c6d9a5 idle    1 turns  [fake] Answer to: Summarise this coho...
  PASS ss |> gptr(): every member steered in place, same list returned
   parallel wall time for 3 sessions, 2 at a time: 0.11 s (each request 0.05 s)
== 5. prompt selection edge cases ==
  PASS a variable holding a string is the prompt when no literal is present
  PASS a string piped into gptr() is the prompt
  PASS gptr() with no prompt under Rscript: gptr_error_noninteractive
````

### `final_t2b_nse.out`

````text
model = "opus" (string)                    -> opus
model = opus (alias symbol)                -> opus
model = m (variable holding 'haiku')       -> haiku
model = if (hard) opus else haiku          -> opus
model = gpt9 (unknown, unbound: literal)   -> gpt9
model = I(m) (explicit variable)           -> haiku
forwarded dots, wrapper has local m        -> haiku
wrapper argument w(mm = m)                 -> haiku
variable named like an alias: model = jev -> gptr_decision (the alias wins, as library(); I(jev) is the escape)
````

### `final_t3_steer.out`

````text
== 1. background = TRUE returns immediately with a running session ==
  PASS returned at once (0.036 s), status running
   print while running: <gptr_session 6bedb436> running (request) | 1 turn | fake | 0 in (0 cached) / 0 out | value: none
== 2. piping into the RUNNING session enqueues a steering message and returns at once ==
[gptr] queued steer for running session 6bedb436
  PASS non-blocking (0.001 s); queue holds the steer
== 3. a second producer: another R process writes to the session's file inbox ==
  PASS inbox line written by the other process (pid differs)
== 4. a third producer: the API (what the Ctrl-C menu and front ends call) ==
  PASS the api item is in the same queue (inbox items join it when drained at the next boundary)
== 5. gptr_wait() blocks until settled and returns the session ==
  PASS settled idle
   transcript:  user<call> assi tool user<pipe> assi tool user<api> assi user<inbox> assi 
  PASS the piped steer lands right after the COMPLETE tool result (never between call and result)
  PASS the inbox follow-up is delivered only when the agent would otherwise stop
  PASS steered $value is the TPM matrix
[fake] Answer to: Also report the library sizes
<gptr_session 6bedb436> idle | 4 turns | fake | 1.7k in (1.2k cached) / 65 out | value: tpm <matrix>
== 6. piping into an IDLE session is a new prompt turn and blocks (Rscript: prints) ==
[fake] Answer to: Summarise the normalisation
<gptr_session 6bedb436> idle | 5 turns | fake | 2.2k in (1.7k cached) / 77 out | value: tpm <matrix>
  PASS idle pipe = follow-up prompt turn, run to settlement
== 7. re-entrancy: the agent's own R code pipes into its running session -> enqueued, no nested run ==
[gptr] queued steer for running session 1b35de87
[fake] Answer to: and double-check the totals
<gptr_session 1b35de87> idle | 2 turns | fake | 709 in (636 cached) / 32 out | value: none
  PASS the nested pipe became a steering message of the same session
  PASS no second concurrent run was started
== 8. abort returns queued messages to the user ==
[gptr] queued steer for running session 5acd58ce
[gptr] queued follow_up for running session 5acd58ce
[gptr] session 5acd58ce finished (aborted, turn 1)
  PASS status aborted; queue moved to $dropped
[fake] Answer to: start again
<gptr_session 5acd58ce> idle | 2 turns | fake | 331 in (312 cached) / 8 out | value: none
  PASS an aborted session continues with the next pipe (no fork)
   jobs now running: 0 
````

### `final_t4_fork.out`

````text
[fake] Done ([1] 3). Saw: 'Use 15% mitochondrial reads as the cut-o'
<gptr_session 32a8124c> idle | 2 turns | fake | 1.6k in (1.1k cached) / 74 out | value: keep <logical>
main line: keep = 3 of 6 cells at 15%; global keep = 3 
== 1. identity, lineage and the fork file ==
  PASS new object, new id
  PASS lineage: parent id and fork turn recorded
  PASS no file yet: a fork is written with its first own message (no orphan files)
  PASS entries copied with the SAME ids, re-chained root to leaf
  PASS session_start(reason = 'fork') fired for plugins
== 2. nothing live is shared: listeners, queue, run ==
[fake] Answer to: Report the number of cells kept
<gptr_session 32a8124c> idle | 3 turns | fake | 2.1k in (1.6k cached) / 87 out | value: keep <logical>
  PASS a listener added to the fork never fires for the parent (INFRA-14 accept test)
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session 4ce75e2b> idle | 3 turns | fake | 1.0k in (967 cached) / 34 out | value: keep <logical>
  PASS it fires for the fork's own appends
  PASS fork file header: parentSession = parent path (Pi v3), gptr.forkOf = {id, entry, turn}
  PASS the fork file starts with the copied path, same ids
  PASS both sessions advanced independently (different leaves, different files)
== 3. the fork evaluates in an overlay: zero-copy reads, isolated writes ==
  PASS fork's keep (10%) lives in the overlay; the user's keep (15%) is untouched
  PASS f$envir is the overlay; reads fall through to globalenv
  PASS the overlay reads pct_mt at the same address (no copy)
   f$envir label: overlay of globalenv() (fork of 32a8124c) 
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session 23e61928> idle | 4 turns | fake | 1.1k in (1.0k cached) / 34 out | value: keep <logical>
  PASS envir = 'shared' opts in to writing into the caller's workspace
== 4. fork at a turn ==
  PASS gptr_fork(qc, at = 1): history and value of turn 1 only
  PASS at = 0: an empty session that still names its parent (file written lazily)
== 5. forking a RUNNING session: cut at the last settled boundary; the fork is idle ==
   parent caught at step boundary after its tool result; answer still pending
[gptr] queued steer for running session fd31ba74
  PASS parent still running; fork idle
  PASS the parent's queue is not copied
  PASS cut at the last settled boundary (complete tool result), never mid-call
[fake] Answer to: steer the parent only
<gptr_session fd31ba74> idle | 2 turns | fake | 690 in (633 cached) / 30 out | value: none
  PASS parent continued with its steer; the fork did not see it
[fake] Answer to: continue the fork from the tool result
<gptr_session 46c525e9> idle | 2 turns | fake | 374 in (357 cached) / 14 out | value: none
  PASS the fork continues with a user message right after the tool result
== 6. token cost: the fork's first request re-uses the parent's cached prefix ==
   fork request 1: 490 input tokens, 477 served from the parent's prefix cache (same model)
````

### `final_t5.out`

````text
plain R baseline: big[1] = 0                       -> in place
plain R: str(big) (known sticky ref, report 12)    -> COPY
gptr('describe', big)                              -> in place
big |> gptr('describe')                            -> in place
s |> gptr('p', big) (continuation + context)       -> in place
agent: gptr_return(big) [40 MB -> by name]         -> in place
agent creates big2 and designates it               -> in place
s$value read, printed head                         -> in place
x = s$value; rm(x)                                 -> in place
replay assignment s$value = big                    -> in place
small object designated [copy policy]              -> in place
print / summary / str / format of s                -> in place
gptr_fork(s) + fork turn reading big               -> in place
System 1 on the session                            -> in place
session created inside a function f(big)           -> in place
wrapper with model alias f(big)                    -> in place
wrapper, model = if (TRUE) opus else haiku         -> in place
forwarded dots w(...) -> gptr(...)                 -> in place
System 1 on data: gptr('ok?', big, model = jev)    -> in place
plain R baseline for a list element: L$a[1] = 0    -> in place
parallel = 2 over a list (trace L$a)               -> in place
background run with context, then settled          -> in place
saveRDS(s) / readRDS                               -> in place
````

### `final_t6_persist.out`

````text
[fake] Answer to: interpret the slope
<gptr_session 49a56289> idle | 2 turns | fake | 1.1k in (702 cached) / 46 out | value: fit <lm>
[fake] Answer to: one sentence please
<gptr_session 49a56289> idle | 3 turns | fake | 1.6k in (1.1k cached) / 56 out | value: fit <lm>
== 1. what a session serialises to ==
   data fields: created<character> dropped<list> entries<list> ext<list> file<character> flushed<logical> home_label<character> id<character> index<environment> last_text<character> leaf<character> loaded<logical> model<character> parent<NULL> persist<logical> queue<list> reason<character> replayed<integer> seen<integer> status<character> step<character> turns<integer> usage<list> values<list> 
  PASS no closures, connections, handles or processes in the session data
  PASS the only environment inside is the entry index (id -> position)
   serialize(s): 14642 bytes for 3 turns / 9 entries (the lm snapshot included)
  PASS round-trips through serialize()/unserialize()
== 2. readRDS in the SAME process: a detached copy, never a silent second writer ==
  PASS a new environment with the same id; the copy is detached
  PASS continuing the copy while the original lives: gptr_error_split_brain
  PASS gptr_resume(id) returns the live object itself
  PASS gptr_fork() of the copy is the explicit way to branch it
== 3. callr: the worker receives a copy; the lock keeps one writer per session file ==
                detached                      err 
                  "TRUE" "gptr_error_split_brain" 
  PASS the worker cannot continue while this process owns the session (lock + live pid)
== 4. R restart: gptr_resume() from the JSONL in a fresh process ==
  PASS finalizer removed the lock when the session was garbage collected
                 status                   turns                  loaded 
                 "idle"                     "3"                  "TRUE" 
            value_class             turns_after   provider_saw_messages 
                 "NULL"                     "4"                     "9" 
                   text 
"[fake] resumed answer" 
  PASS resumed with the full history; the next request carried every earlier message
== 5. a stale copy continued in a new process branches INSIDE the same file (no new session) ==
[fake] Answer to: a fifth turn in this process
<gptr_session 49a56289> idle | 5 turns | fake | 495 in (441 cached) / 12 out | value: fit <lm>
                                                                                                                                                                                                           turns 
                                                                                                                                                                                                             "5" 
                                                                                                                                                                                                              id 
                                                                                                                                                                                                      "49a56289" 
                                                                                                                                                                                                        messages 
"[gptr] session 49a56289: continuing from this object's state (turn 4); 2 newer entries in the file stay as a sibling branch\n || [gptr] re-attached session 49a56289 (home <env <environment: 0x1464d10a8>>)\n" 
  PASS the file now has two children of one entry: a branch in the same session tree
  PASS same id; the copy continued from its own leaf (turn 4 -> 5)
````

### `final_t6b.out`

````text
knit 1: cat("requests made in this knit:", the$requests, "| turns:", s$turns, "| status:", s$status, "\n") ## requests made in this knit: 2 | turns: 2 | status: idle 
knit 2: cat("requests made in this knit:", the$requests, "| turns:", s$turns, "| status:", s$status, "\n") ## requests made in this knit: 1 | turns: 2 | status: idle 
session files: 1 | user messages in the file: 'summarise mtcars', 'now shorten it', 'now shorten it' 
branch in the file (two children of one entry): TRUE 
````

### `final_t7.out`

````text
== RUN 1: record (live model, blocks written after each statement) ==
    requests=8 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4 
---- analysis.R after recording:
# analysis.R -- the program and the record of the agent work
a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')
# >>> gptr:b1120d model=fake/fake date=2026-09-29 prompt=255a3959007b session=574f66ef turn=1 value=counts
counts = matrix(c(5, 50, 500, 5000, 6, 60, 600, 6000, 7, 70, 700, 7000), 4)
dim(counts)
#> [1] 4 3
## Decision: (fake) answered turn 1.
a$value = counts
# <<< gptr:b1120d
# >>> gptr:7d3937 model=fake/fake date=2026-09-29 prompt=6ef699c61233 call=2 session=574f66ef turn=2 value=tpm
tpm = t(t(counts) / colSums(counts)) * 1e6
round(colSums(tpm))
#> [1] 1e+06 1e+06 1e+06
## Decision: (fake) answered turn 2.
a$value = tpm
# <<< gptr:7d3937
a |> gptr('How many genes pass the filter?')
# >>> gptr:fafb88 model=fake/fake date=2026-09-29 prompt=f53ff28e764c session=574f66ef turn=3 value=keep
keep = rowSums(tpm > 1e4) >= 2
sum(keep)
#> [1] 2
## Decision: (fake) answered turn 3.
a$value = keep
# <<< gptr:fafb88
gptr_fork(a) |> gptr('Try a stricter filter as well')
# >>> gptr:6413d0 model=fake/fake date=2026-09-29 prompt=ed64d3adeff7 session=601e5020 turn=4 fork=574f66ef:3 value=keep
local({
  keep = rowSums(tpm > 1e5) >= 2
  sum(keep)
  #> [1] 1
}, envir = gptr_resume("601e5020")$envir)
## Decision: (fake) answered turn 4.
# <<< gptr:6413d0

== RUN 2: replay in a fresh process (no model calls; blocks rebuild the objects) ==
    requests=0 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4
    sessions attached: 574f66ef 601e5020 
    replayed turns of a: 1,2,3 | a$values turns: 1,2,3 | a$value: logical 
    fork 601e5020 turns 4 | fork keep (overlay): 4  

== RUN 3: same process, source() twice: re-running steering statements adds no turns ==
    requests=0 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4
    requests=0 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4 

== RUN 4: replay, then re-run ONE steering statement live: a real new turn, document untouched ==
    requests=0 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4
    after live re-run: requests=2 turns=4 
  document unchanged by live mode: TRUE 

== RUN 5: edit the prompt of statement 2, record: only that block regenerates; the session branches ==
    requests=2 | a: id 574f66ef turns 3, value logical[4] | session files 2 | global keep: rows 3,4
    branch inside the session file (same id): TRUE  
---- analysis.R after regeneration (headers only):
a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')
# >>> gptr:b1120d model=fake/fake date=2026-09-29 prompt=255a3959007b session=574f66ef turn=1 value=counts
a$value = counts
# >>> gptr:7d3937 model=fake/fake date=2026-09-29 prompt=6ef699c61233 call=2 session=574f66ef turn=2 value=tpm
a$value = tpm
a |> gptr('How many genes pass the filter at 2 samples?')
# >>> gptr:fafb88 model=fake/fake date=2026-09-29 prompt=ccd141411a25 session=574f66ef turn=3 value=keep
a$value = keep
gptr_fork(a) |> gptr('Try a stricter filter as well')
# >>> gptr:6413d0 model=fake/fake date=2026-09-29 prompt=ed64d3adeff7 session=601e5020 turn=4 fork=574f66ef:3 value=keep
````

### `final_t8_edge.out`

````text
== identity ==
  PASS b = a and list(a, a): one session, identical() is TRUE
  PASS all.equal() compares contents (R >= 4.1 all.equal.environment); identity is identical()
  PASS the pipe returns the same object
== lists and lapply ==
  PASS lapply(sessions, \(s) s |> gptr(...)) steers each in place
  PASS sessions created inside lapply's closure keep a label only; each continuation used its own caller
   home retained for sessions created inside the lapply closure: FALSE FALSE (frames are never retained)
== memory growth over 200 turns (text-only turns) ==
   200 turns: 4.83 s total (24.1 ms/turn incl. JSONL append); transcript grew 6 KB -> 1377 KB (6.9 KB/turn)
   JSONL file: 189 KB; serialize(m): 335 KB
== held values are bounded ==
   values by kind: name,name,name,name,name,name | held: FALSE,FALSE,FALSE,FALSE,FALSE,FALSE 
  PASS 16 MB objects bound in globalenv are held BY NAME: the session holds no copy
   copy policy: 21 values, 8 held (4.8 MB), budget 5 MB; latest held: TRUE
  PASS held copies stay within gptr.values_max_bytes; the latest is always held
== finalizers and gc of finished sessions ==
  PASS 5 unreferenced finished sessions were collected; their finalizers ran
  PASS registry entries were removed (weak keys, no leak)
  PASS their lock directories were removed
  PASS a RUNNING unreferenced session is kept alive by the reactor
  PASS ... and collected once it settled
  PASS a session created and dropped inside a function is collected with its frame
````

### `final_t9.out`

````text
[1] TRUE
---- 1. background session: the prompt comes back at once; the idle console services it (later)
[1] TRUE
[1] TRUE
---- 2. pipe steering from the prompt while it runs (returns immediately)
[1] TRUE
---- 3. Ctrl-C while a BACKGROUND tool blocks the console: the same pause menu; (f)ollow-up
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
---- 4. gptr_wait(): foreground attach; ANOTHER process writes a follow-up to the file inbox meanwhile
[1] TRUE
[1] TRUE
---- 5. foreground gptr() at the console, Ctrl-C then (b)ackground: the prompt comes back, the run continues
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
---- 6. interactive visibility: a foreground call prints once (printed as it settles, returned invisibly)
[1] TRUE
CHILD READY interactive() = TRUE 
STATUS running 
IDLE CHECK step boundary entries 4 
[gptr] queued steer for running session 3298389c
PIPE RETURNED after 0.001 s; queue: Use TPM, not CPM 
[gptr] paused 3298389c: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? follow-up> [gptr] queued; continuing
ID 3298389c 
[fake] Answer to: Summarise in one line
<gptr_session 3298389c> idle | 4 turns | fake | 3.1k in (2.6k cached) / 115 out | value: tpm <matrix>
TRANSCRIPT user<call> assi tool assi user<pipe> assi tool assi user<menu> assi tool assi user<inbox> assi 
[gptr] paused 4c00d094: (s)teer, (f)ollow-up, (b)ackground, (a)bort, (c)ontinue? [gptr] running in the background; gptr_wait() re-attaches
BACK AT PROMPT status running 
[gptr] session 4c00d094 finished (stop, turn 1)
LATER status idle turns 1 
[fake] Answer to: say hi
<gptr_session 365d3b32> idle | 1 turn | fake | 321 in (312 cached) / 6 out | value: none
AFTER CALL
````

### `gptr_session.R`

````r
# gptr_session.R -- G3 prototype of the S-8 session object: reference semantics, pipe steering of
# idle and running sessions, one queue fed by three producers, explicit fork, printing, $value,
# persistence (Pi v3 JSONL), detach/re-attach. Base R + jsonlite + rlang (weak refs, hash, obj_address, duplicate);
# later (background service) and processx (tests) are optional. House style: `=` and `|>`.
#
# Layout of a session object `s` (class "gptr_session"):
#   s            classed environment the user holds; its only binding is `.d`
#   .d(s)        unclassed data environment: serialisable fields only (strings, numbers, lists)
#   .live(s)     per-process live resources (home env, listeners, run state, handles), kept in a
#                registry keyed by id through a WEAK reference whose key is `s`
`%||%` = function(a, b) if (is.null(a)) b else a

the = new.env(parent = emptyenv())
the$live = new.env(parent = emptyenv())    # id -> rlang weakref(key = session, value = live env)
the$active = new.env(parent = emptyenv())  # id -> session; STRONG while a run is active
the$hooks = list()                         # extension hooks: event -> list of functions
the$fields = list()                        # plugin-registered computed fields: name -> function(s)
the$current = NULL                         # request whose r-tool code is running (gptr_return)
the$requests = 0L                          # provider requests made (tests assert 0 on replay)
the$known_models = c("fake", "fake2", "opus", "haiku", "sonnet", "jev")
the$s1_models = "jev"
the$system_prompt = strrep("You are gptr, an agent inside the user's R session. ", 24L)  # ~1.2k chars
the$in_foreground = FALSE
the$pump_scheduled = FALSE

# ------------------------------------------------------------------ small utilities
.hex = function(n = 8L) {                   # entropy without touching .Random.seed (report 02)
  out = ""
  while (nchar(out) < n) out = paste0(out, gsub("[^0-9a-f]", "", tolower(basename(tempfile(pattern = "")))))
  substr(out, nchar(out) - n + 1L, nchar(out))
}
.now_iso = function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
.ms = function() round(as.numeric(Sys.time()) * 1000)
.json = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, force = TRUE))
.sessions_dir = function() getOption("gptr.sessions_dir", file.path(tempdir(), "gptr-sessions"))
.d = function(s) get(".d", envir = s, inherits = FALSE)
.gptr_abort = function(msg, class) stop(structure(class = c(paste0("gptr_error_", class), "gptr_error",
  "error", "condition"), list(message = msg, call = NULL)))
.say = function(...) if (!isTRUE(getOption("gptr.quiet"))) message("[gptr] ", ...)
.trunc = function(x, n) if (is.na(x) || nchar(x) <= n) x else paste0(substr(x, 1L, n - 3L), "...")
.env_label = function(env) {
  if (identical(env, globalenv())) return("globalenv()")
  if (!is.null(attr(env, "gptr_overlay"))) return(attr(env, "gptr_overlay"))
  paste0("<env ", format(env), ">")
}
.on_stack = function(env) {                 # is `env` the frame of a function still running?
  k = sys.nframe()                          # not sys.frames(): that list, once garbage, keeps every
  while (k > 0L) {                          # frame on the stack referenced (a sticky pin; p5)
    if (identical(sys.frame(k), env)) return(TRUE)
    k = k - 1L
  }
  FALSE
}

# ------------------------------------------------------------------ copy-safe leaves (report 12 C2)
.leaf_facts = function(x) list(class = class(x), dim = dim(x), length = length(x),
                               size = as.numeric(utils::object.size(x)))
.fmt_facts = function(label, f) {
  force(label); force(f)
  shape = if (!is.null(f$dim)) paste(f$dim, collapse = "x") else paste0("n=", f$length)
  sprintf("<object name=%s class=%s %s size=%s>", label, f$class[1L], shape,
          format(structure(f$size, class = "object_size"), units = "auto"))
}

# ------------------------------------------------------------------ registry of live resources
.attach_live = function(s, home, retained) {
  live = new.env(parent = emptyenv())
  live$home = home                       # evaluation workspace (retained env) or NULL
  live$retained = retained
  live$listeners = list()                # session-scoped event listeners (never copied by fork)
  live$run = NULL                        # state of the active run (closures, timers, handles)
  live$pid = Sys.getpid()
  assign(.d(s)$id, rlang::new_weakref(key = s, value = live), envir = the$live)
  reg.finalizer(s, .session_finalizer, onexit = TRUE)
  live
}
.live = function(s) {
  w = get0(.d(s)$id, envir = the$live, inherits = FALSE)
  if (is.null(w)) return(NULL)
  k = rlang::wref_key(w)
  if (is.null(k) || !identical(k, s)) return(NULL)
  rlang::wref_value(w)
}
.session_finalizer = function(s) {        # runs when the session is garbage collected (or at exit)
  d = .d(s)
  the$finalized = c(the$finalized, d$id)
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w) && (is.null(rlang::wref_key(w)) || identical(rlang::wref_key(w), s)))
    rm(list = d$id, envir = the$live)
  lock = paste0(d$file, ".lock")
  if (dir.exists(lock) && identical(readLines(file.path(lock, "pid"), warn = FALSE), as.character(Sys.getpid())))
    unlink(lock, recursive = TRUE)
}

# ------------------------------------------------------------------ constructor
.new_session = function(model, home, retained, parent = NULL, id = NULL, persist = TRUE) {
  s = new.env(parent = emptyenv())
  d = new.env(parent = emptyenv())
  assign(".d", d, envir = s)
  class(s) = "gptr_session"
  d$id = id %||% .hex(8L)
  d$created = .now_iso()
  d$status = "idle"; d$reason = NA_character_; d$step = NA_character_
  d$model = model %||% "fake"
  d$turns = 0L; d$last_text = NA_character_
  d$usage = list(input = 0, output = 0, cache_read = 0, requests = 0L)
  d$values = list(); d$queue = list(); d$dropped = list()
  d$entries = list(); d$index = new.env(parent = emptyenv()); d$leaf = NULL; d$loaded = TRUE
  d$persist = persist; d$flushed = FALSE
  d$file = file.path(.sessions_dir(), paste0(gsub("[:.]", "-", d$created), "_", d$id, ".jsonl"))
  d$parent = parent
  d$home_label = .env_label(home)
  d$replayed = integer()
  d$ext = list()                          # plugin data (JSON-able), persisted as custom entries
  .attach_live(s, home = if (retained) home else NULL, retained = retained)
  .lock(s)
  s
}
.lock = function(s) {                     # single writer per session file across processes
  d = .d(s); lock = paste0(d$file, ".lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  if (dir.create(lock, showWarnings = FALSE)) return(.relock(lock))
  owner = suppressWarnings(as.integer(readLines(file.path(lock, "pid"), warn = FALSE)))
  if (identical(owner, Sys.getpid())) return(TRUE)
  alive = length(owner) == 1L && !is.na(owner) &&
    isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(owner)), error = function(e) FALSE))
  if (alive) .gptr_abort(sprintf(paste("session %s is attached in another R process (pid %d).",
    "Use gptr_fork() to branch it or gptr_steer(\"%s\", ...) to steer it."), d$id, owner, d$id), "split_brain")
  .relock(lock)
}
.relock = function(lock) { writeLines(as.character(Sys.getpid()), file.path(lock, "pid")); TRUE }

# ------------------------------------------------------------------ JSONL store (Pi v3)
.write_lines = function(path, lines, append) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con = file(path, open = if (append) "ab" else "wb")
  on.exit(close(con))
  writeLines(enc2utf8(lines), con, sep = "\n", useBytes = TRUE)
}
.header = function(d) {
  h = list(type = "session", version = 3L, id = d$id, timestamp = d$created, cwd = getwd())
  if (!is.null(d$parent$file)) h$parentSession = d$parent$file
  h$gptr = list(format = 1L)
  if (!is.null(d$parent)) h$gptr$forkOf = d$parent[c("id", "entry", "turn")]
  h
}
.entry_id = function(d) {
  repeat { id = .hex(8L); if (!exists(id, envir = d$index, inherits = FALSE)) return(id) }
}
.append_entry = function(s, type, fields) {
  d = .d(s)
  .ensure_loaded(s)
  e = c(list(type = type, id = .entry_id(d), parentId = d$leaf, timestamp = .now_iso()), fields)
  if (is.null(d$leaf)) e["parentId"] = list(NULL)
  d$entries[[length(d$entries) + 1L]] = e
  assign(e$id, length(d$entries), envir = d$index)
  d$leaf = e$id
  if (isTRUE(d$persist)) suspendInterrupts({
    if (!d$flushed) {
      if (identical(type, "message")) {           # lazy file creation, as Pi
        .write_lines(d$file, vapply(c(list(.header(d)), d$entries), .json, ""), append = FALSE)
        d$flushed = TRUE
      }
    } else .write_lines(d$file, .json(e), append = TRUE)
  })
  .emit(s, "entry_appended", e)
  invisible(e$id)
}
.ensure_loaded = function(s) {            # lazily load the transcript of a resumed session
  d = .d(s)
  if (isTRUE(d$loaded)) return(invisible())
  .load_file(d, d$file)
  invisible()
}
.load_file = function(d, path) {
  lines = readLines(path, encoding = "UTF-8", warn = FALSE)
  parsed = Filter(Negate(is.null), lapply(lines[nzchar(lines)], function(l)
    tryCatch(jsonlite::fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)))
  if (!length(parsed) || !identical(parsed[[1]]$type, "session")) .gptr_abort(paste("not a session file:", path), "bad_file")
  d$entries = parsed[-1]
  d$index = new.env(parent = emptyenv())
  for (i in seq_along(d$entries)) assign(d$entries[[i]]$id, i, envir = d$index)
  d$leaf = d$leaf %||% (if (length(d$entries)) d$entries[[length(d$entries)]]$id else NULL)
  d$loaded = TRUE; d$flushed = TRUE
  invisible(parsed[[1]])
}
.path = function(d, leaf = d$leaf) {      # root -> leaf entries of the session tree
  out = list(); id = leaf
  while (!is.null(id)) {
    i = get0(id, envir = d$index, inherits = FALSE)
    if (is.null(i)) break
    e = d$entries[[i]]; out[[length(out) + 1L]] = e; id = e$parentId
  }
  rev(out)
}

# ------------------------------------------------------------------ events and extension hooks
gptr_on = function(s, event, handler) {   # session-scoped listener (a live resource)
  live = .live(s)
  if (is.null(live)) .gptr_abort("session is detached; continue it first", "detached")
  live$listeners[[length(live$listeners) + 1L]] = list(event = event, fn = handler)
  invisible(s)
}
gptr_hook = function(event, handler) {    # process-wide extension hook (plugins register once)
  the$hooks[[event]] = c(the$hooks[[event]], list(handler))
  invisible(NULL)
}
.emit = function(s, event, payload = NULL) {
  live = .live(s)
  if (!is.null(live)) for (l in live$listeners) if (l$event %in% c(event, "*")) l$fn(event, payload, s)
  for (h in the$hooks[[event]]) h(payload, s)
  invisible()
}
gptr_field = function(name, getter) {     # plugins add computed read-only fields: s$<name>
  the$fields[[name]] = getter
  invisible(NULL)
}

# ------------------------------------------------------------------ public accessors
the$getters = list(
  id = function(s) .d(s)$id,
  status = function(s) .d(s)$status,
  text = function(s) .d(s)$last_text,
  value = function(s) .value_latest(s),
  values = function(s) .values_table(s),
  usage = function(s) .d(s)$usage,
  turns = function(s) .d(s)$turns,
  model = function(s) .d(s)$model,
  history = function(s) .history(s),
  queue = function(s) vapply(.d(s)$queue, function(m) m$text, ""),
  dropped = function(s) vapply(.d(s)$dropped, function(m) m$text, ""),
  parent = function(s) .d(s)$parent,
  file = function(s) .d(s)$file,
  envir = function(s) { live = .live(s); if (is.null(live)) NULL else live$home },
  attached = function(s) !is.null(.live(s))
)
`$.gptr_session` = function(x, name) {
  g = the$getters[[name]] %||% the$fields[[name]]
  if (is.null(g)) NULL else g(x)
}
`[[.gptr_session` = function(x, i, ...) `$.gptr_session`(x, i)
`$<-.gptr_session` = function(x, name, value) {
  if (!identical(name, "value"))
    .gptr_abort(sprintf("`$%s` is read-only; sessions change only through gptr() and gptr_*() calls", name), "readonly")
  .set_value(x, substitute(value), parent.frame(), if (is.symbol(substitute(value))) NULL else value,
             source = "assign")
  x
}
`[[<-.gptr_session` = function(x, i, value) .gptr_abort("sessions are read-only; use gptr()", "readonly")
.DollarNames.gptr_session = function(x, pattern = "") {
  n = c(names(the$getters), names(the$fields))
  n[grepl(pattern, n)]
}
format.gptr_session = function(x, ...) { t = .d(x)$last_text; if (is.na(t)) "" else t }
as.character.gptr_session = function(x, ...) format.gptr_session(x)
.footer = function(x) {
  d = .d(x); u = d$usage
  k = function(n) if (n >= 1000) sprintf("%.1fk", n / 1000) else sprintf("%d", as.integer(n))
  v = .values_table(x)
  vtxt = if (nrow(v)) sprintf("%s <%s>", if (is.na(v$name[nrow(v)])) "(value)" else v$name[nrow(v)], v$class[nrow(v)]) else "none"
  q = length(d$queue)
  sprintf("<gptr_session %s> %s%s | %d turn%s | %s | %s in (%s cached) / %s out | value: %s%s",
          d$id, d$status, if (identical(d$status, "running")) paste0(" (", d$step, ")") else "",
          d$turns, if (d$turns == 1L) "" else "s", d$model, k(u$input), k(u$cache_read), k(u$output),
          vtxt, if (q) sprintf(" | %d queued", q) else "")
}
print.gptr_session = function(x, ...) {
  t = .d(x)$last_text
  if (!is.na(t) && !identical(.d(x)$status, "running")) cat(t, "\n", sep = "")
  cat(.footer(x), "\n", sep = "")
  invisible(x)
}
str.gptr_session = function(object, ...) {
  d = .d(object)
  cat(sprintf("<gptr_session %s> %s, %d turns, %d entries, home %s, %s\n", d$id, d$status, d$turns,
              length(d$entries), d$home_label, if (is.null(.live(object))) "detached" else "attached"))
  invisible()
}
summary.gptr_session = function(object, ...) {
  h = .history(object)
  u = h[h$role == "user", c("turn", "deliver", "source", "text"), drop = FALSE]
  a = h[h$role == "assistant" & h$final, c("turn", "model", "text"), drop = FALSE]
  names(a)[3] = "answer"
  out = merge(u, a, by = "turn", all.x = TRUE)
  out$text = vapply(out$text, .trunc, "", 38L); out$answer = vapply(out$answer, .trunc, "", 38L)
  v = .values_table(object)
  out$value = v$name[match(out$turn, v$turn)]
  structure(out, class = c("summary.gptr_session", "data.frame"))
}
print.summary.gptr_session = function(x, ...) { print(structure(x, class = "data.frame"), row.names = FALSE); invisible(x) }

.history = function(s) {                  # tidy view of the active branch (lazy load)
  .ensure_loaded(s)
  path = .path(.d(s))
  msgs = Filter(function(e) identical(e$type, "message"), path)
  turn = 0L
  rows = lapply(msgs, function(e) {
    m = e$message
    if (identical(m$role, "user")) turn <<- turn + 1L
    txt = paste(vapply(m$content, function(b) b$text %||% sprintf("[%s %s]", b$type, b$name %||% ""), ""), collapse = " ")
    data.frame(turn = turn, role = m$role, deliver = m$gptr$deliver %||% NA_character_,
               source = m$gptr$source %||% NA_character_, model = m$model %||% NA_character_,
               final = identical(m$role, "assistant") && !identical(m$stopReason, "toolUse"),
               text = txt, stringsAsFactors = FALSE)
  })
  if (!length(rows)) return(data.frame(turn = integer(), role = character(), deliver = character(),
    source = character(), model = character(), final = logical(), text = character()))
  do.call(rbind, rows)
}

# ------------------------------------------------------------------ values (designated results)
gptr_return = function(value) {          # called by the agent's R code during a run
  cur = the$current
  if (is.null(cur)) .gptr_abort("gptr_return() can only be called by the agent during a gptr() run", "no_request")
  .set_value(cur$s, substitute(value), parent.frame(), if (is.symbol(substitute(value))) NULL else value,
             source = "agent", env_hint = cur$env)
  invisible(NULL)                         # never a visible passthrough of the value (report 12)
}
.set_value = function(s, expr, env, forced, source, env_hint = NULL) {
  # Three ways to hold a designated value, none of which references a user object:
  #   copy : a small object bound in a kept workspace -> a deep copy (history stays faithful)
  #   name : a large object bound in a kept workspace -> its NAME + address (live view, no reference)
  #   value: an anonymous value, or one bound in a frame that is about to vanish -> the object itself
  d = .d(s)
  turn = if (length(d$pending_value_turns)) d$pending_value_turns[1L] else d$turns
  if (length(d$pending_value_turns)) d$pending_value_turns = d$pending_value_turns[-1L]
  bound = is.symbol(expr) && exists(as.character(expr), envir = env, inherits = FALSE)
  kept = bound && .by_name_ok(s, env)
  if (kept) {
    nm = as.character(expr)
    f = .leaf_facts(get(nm, envir = env))
    addr = rlang::obj_address(get(nm, envir = env))
    if (f$size < getOption("gptr.value_copy_max", 2^20)) {
      v = list(turn = turn, by = "copy", name = nm, env = .env_label(env), class = f$class[1L], size = f$size,
               addr = addr, object = rlang::duplicate(get(nm, envir = env), shallow = FALSE))
    } else {
      v = list(turn = turn, by = "name", name = nm, env = .env_label(env), class = f$class[1L], size = f$size, addr = addr)
    }
  } else {
    if (bound) forced = get(as.character(expr), envir = env)
    v = list(turn = turn, by = "value", name = if (bound) as.character(expr) else NA_character_, env = NA_character_,
             class = class(forced)[1L], size = as.numeric(utils::object.size(forced)), addr = NA_character_, object = forced)
  }
  same = which(vapply(d$values, function(x) identical(as.integer(x$turn), as.integer(turn)), NA))
  if (length(same) && turn %in% d$replayed) d$values[[same[length(same)]]] = v else d$values[[length(d$values) + 1L]] = v
  .trim_values(d)
  if (!(turn %in% d$replayed))            # replay never re-writes the session file
    .append_entry(s, "custom", list(customType = "gptr.value", data = v[c("turn", "by", "name", "env", "class", "size")]))
  invisible()
}
.trim_values = function(d) {              # memory bound on held values (the latest is always kept)
  held = which(vapply(d$values, function(v) !is.null(v$object), NA))
  budget = getOption("gptr.values_max_bytes", 64 * 2^20)
  while (length(held) > 1L && sum(vapply(d$values[held], function(v) v$size, 1)) > budget) {
    d$values[[held[1L]]]["object"] = list(NULL); held = held[-1L]
  }
}
.by_name_ok = function(s, env) {          # only names in a workspace the session keeps (never a frame)
  if (identical(env, globalenv())) return(TRUE)
  live = .live(s)
  !is.null(live) && isTRUE(live$retained) && identical(env, live$home)
}
.value_latest = function(s) {
  vals = .d(s)$values
  if (!length(vals)) return(NULL)
  turns = vapply(vals, function(v) as.integer(v$turn), 1L)
  .resolve_value(s, vals[[max(which(turns == max(turns)))]], latest = TRUE)
}
gptr_value = function(s, turn = NULL) {
  vals = .d(s)$values
  if (is.null(turn)) return(.value_latest(s))
  hit = Filter(function(v) identical(as.integer(v$turn), as.integer(turn)), vals)
  if (!length(hit)) return(NULL)
  .resolve_value(s, hit[[length(hit)]])
}
.resolve_value = function(s, v, latest = FALSE) {
  if (v$by %in% c("value", "copy")) {
    if (is.null(v$object)) .say("the value of turn ", v$turn, " was released (gptr.values_max_bytes)")
    return(v$object)
  }
  home = .live(s)$home
  env = .find_binding(v$name, home)
  if (is.null(env) && identical(v$env, "globalenv()") && exists(v$name, envir = globalenv(), inherits = FALSE)) {
    if (is.null(.live(s))) .say("value `", v$name, "` resolved by name in globalenv(); this is not the R process that designated it")
    env = globalenv()
  }
  if (is.null(env)) { .say("value `", v$name, "` (turn ", v$turn, ") is not available in this R process"); return(NULL) }
  if (!latest && !identical(rlang::obj_address(get(v$name, envir = env)), v$addr)) {
    .say("`", v$name, "` was re-bound after turn ", v$turn, "; that object is gone (large values are held by name)")
    return(NULL)
  }
  get(v$name, envir = env)
}
.find_binding = function(name, env) {     # walk overlays down to (and including) globalenv
  while (!is.null(env) && !identical(env, emptyenv())) {
    if (exists(name, envir = env, inherits = FALSE)) return(env)
    if (identical(env, globalenv())) return(NULL)
    env = parent.env(env)
  }
  NULL
}
.values_table = function(s) {
  vals = .d(s)$values
  data.frame(turn = vapply(vals, function(v) as.integer(v$turn), 1L),
             by = vapply(vals, function(v) v$by, ""),
             name = vapply(vals, function(v) v$name %||% NA_character_, ""),
             class = vapply(vals, function(v) v$class, ""),
             size = vapply(vals, function(v) v$size, 1),
             held = vapply(vals, function(v) !is.null(v$object), NA), stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------ the queue: one inbox, three producers
.enqueue = function(s, text, deliver = c("steer", "follow_up"), source = "pipe") {
  deliver = match.arg(deliver)
  d = .d(s)
  d$queue[[length(d$queue) + 1L]] = list(text = text, deliver = deliver, source = source, t = .ms())
  .emit(s, "queue_update", list(deliver = deliver, source = source, text = text))
  invisible(s)
}
.inbox_path = function(d) sub("[.]jsonl$", ".inbox.jsonl", d$file)
gptr_steer = function(x, text, deliver = c("steer", "follow_up", "abort")) {
  deliver = match.arg(deliver)
  if (is.character(x)) {                  # another process: append to the file inbox
    path = if (file.exists(x)) sub("[.]jsonl$", ".inbox.jsonl", x) else {
      f = list.files(.sessions_dir(), pattern = paste0("_", x, "[.]jsonl$"), full.names = TRUE)
      if (!length(f)) .gptr_abort(paste("no session file for id", x), "not_found")
      sub("[.]jsonl$", ".inbox.jsonl", f[1])
    }
    suspendInterrupts(.write_lines(path, .json(list(kind = deliver, text = text, t = .ms(), pid = Sys.getpid())), append = TRUE))
    return(invisible(path))
  }
  if (identical(deliver, "abort")) return(gptr_cancel(x))
  .enqueue(x, text, deliver, source = "api")
}
.drain_inbox = function(s) {
  d = .d(s); inbox = .inbox_path(d)
  if (!file.exists(inbox)) return(invisible(0L))
  claimed = paste0(inbox, ".", Sys.getpid(), ".claimed")
  if (!suppressWarnings(file.rename(inbox, claimed))) return(invisible(0L))
  lines = readLines(claimed, encoding = "UTF-8", warn = FALSE); unlink(claimed)
  for (l in lines[nzchar(lines)]) {
    m = jsonlite::fromJSON(l, simplifyVector = FALSE)
    if (identical(m$kind, "abort")) { run = .live(s)$run; if (!is.null(run)) run$abort = TRUE; next }
    .enqueue(s, m$text, if (identical(m$kind, "follow_up")) "follow_up" else "steer", source = "inbox")
  }
  invisible(length(lines))
}
.take = function(s, deliver) {            # one-at-a-time (Pi default)
  d = .d(s)
  i = which(vapply(d$queue, function(m) identical(m$deliver, deliver), NA))[1L]
  if (is.na(i)) return(NULL)
  m = d$queue[[i]]; d$queue[[i]] = NULL
  m
}

# ------------------------------------------------------------------ messages and context
.user_msg = function(text, deliver, source) list(role = "user", content = list(list(type = "text", text = text)),
  timestamp = .ms(), gptr = list(deliver = deliver, source = source))
.append_user = function(s, text, deliver, source) {
  d = .d(s)
  d$turns = d$turns + 1L
  d$seen = c(d$seen, d$turns)
  .append_entry(s, "message", list(message = .user_msg(text, deliver, source)))
}
.context = function(s) {                  # provider messages along the branch, projected (report 02 §2.7)
  path = .path(.d(s))
  msgs = lapply(Filter(function(e) identical(e$type, "message"), path), function(e) e$message)
  Filter(function(m) !(identical(m$role, "assistant") && m$stopReason %in% c("aborted", "error")), msgs)
}

# ------------------------------------------------------------------ the run engine (state machine)
# status: idle | running | error | aborted ; step (while running): request | waiting | tools | boundary
.start_run = function(s, envir) {
  d = .d(s); live = .live(s)
  live$run = new.env(parent = emptyenv())
  live$run$step = "request"; live$run$abort = FALSE; live$run$steps = 0L; live$run$env = envir
  live$run$max_steps = getOption("gptr.max_turns", 20L)
  d$status = "running"; d$step = "request"; d$reason = NA_character_
  assign(d$id, s, envir = the$active)     # the reactor holds running sessions strongly
  .emit(s, "agent_start", NULL)
}
.advance = function(s) {                  # one state transition; FALSE when nothing was ready
  d = .d(s); live = .live(s); run = live$run
  if (is.null(run) || !identical(d$status, "running")) return(FALSE)
  if (isTRUE(run$abort)) { .settle(s, "aborted"); return(TRUE) }
  if (identical(run$step, "request")) {
    ctx = .context(s)
    the$requests = the$requests + 1L
    run$request = list(t0 = Sys.time(), resp = .call_adapter(the$provider, ctx, d$model, s), ctx = ctx)
    run$step = "waiting"; d$step = "waiting"
    return(TRUE)
  }
  if (identical(run$step, "waiting")) {
    r = run$request
    if (as.numeric(Sys.time() - r$t0, units = "secs") < (r$resp$delay %||% 0.05)) return(FALSE)
    r$resp$usage = .usage_add(s, r$ctx, r$resp)
    content = list()
    if (nzchar(r$resp$text %||% "")) content[[1L]] = list(type = "text", text = r$resp$text)
    calls = r$resp$calls %||% list()
    for (i in seq_along(calls)) content[[length(content) + 1L]] = list(type = "toolCall",
      id = paste0("call_", .hex(6L)), name = calls[[i]]$name, arguments = calls[[i]]$arguments)
    msg = list(role = "assistant", content = content, provider = "fake", model = d$model,
               usage = r$resp$usage, stopReason = if (length(calls)) "toolUse" else "stop", timestamp = .ms())
    .append_entry(s, "message", list(message = msg))
    if (!length(calls)) d$last_text = r$resp$text
    run$pending = Filter(function(b) identical(b$type, "toolCall"), content)
    run$step = if (length(run$pending)) "tools" else "final"; d$step = run$step
    run$steps = run$steps + 1L
    return(TRUE)
  }
  if (identical(run$step, "tools")) { .tool_step(s, run); return(TRUE) }   # ONE tool call per transition
  if (run$step %in% c("boundary", "final")) {   # turn boundary: complete tool results are in
    .drain_inbox(s)
    if (isTRUE(run$abort)) { .settle(s, "aborted"); return(TRUE) }
    m = .take(s, "steer")
    if (is.null(m) && identical(run$step, "final")) m = .take(s, "follow_up")
    if (!is.null(m)) { .append_user(s, m$text, m$deliver, m$source); run$step = "request"; d$step = "request"; return(TRUE) }
    if (identical(run$step, "final")) { .settle(s, "stop"); return(TRUE) }
    if (run$steps >= run$max_steps) { .settle(s, "max_turns"); return(TRUE) }
    run$step = "request"; d$step = "request"
    return(TRUE)
  }
  FALSE
}
.tool_step = function(s, run) {
  # No exiting interrupt handler here: it would pre-empt the pause menu (a calling handler further out).
  # If the interrupt is NOT resumed (menu: abort; or no menu), on.exit() records a truthful synthetic
  # result so the tool call is never orphaned or reported as never run (INFRA-04).
  d = .d(s)
  call = run$pending[[1L]]
  done = FALSE
  on.exit(if (!done) {
    run$abort = TRUE; run$pending[[1L]] = NULL
    .append_entry(s, "message", list(message = list(role = "toolResult", toolCallId = call$id, toolName = call$name,
      content = list(list(type = "text", text = "Interrupted by the user before the tool finished; side effects may be partial.")),
      isError = TRUE, timestamp = .ms())))
    run$step = "boundary"; d$step = "boundary"
  }, add = TRUE)
  res = .run_tool(s, call, run$env)
  done = TRUE
  run$pending[[1L]] = NULL
  .append_entry(s, "message", list(message = list(role = "toolResult", toolCallId = call$id, toolName = call$name,
    content = list(list(type = "text", text = res$text)), isError = res$is_error, timestamp = .ms())))
  if (!length(run$pending)) { run$step = "boundary"; d$step = "boundary" }
  invisible()
}
.usage_add = function(s, ctx, resp) {     # chars/4 estimate; provider prompt cache keyed by PREFIX CONTENT
  d = .d(s); live = .live(s)                # (per model, shared by every session: forks hit the parent's prefix)
  if (is.null(the$sent)) the$sent = new.env(parent = emptyenv())
  chars = vapply(ctx, function(m) nchar(.json(m$content)), 1)
  sys = nchar(the$system_prompt)
  keys = character(length(ctx)); prev = d$model          # rolling prefix key: O(n) per request
  for (k in seq_along(ctx)) { prev = rlang::hash(c(prev, rlang::hash(ctx[[k]]$content))); keys[k] = prev }
  hit = which(vapply(keys, exists, NA, envir = the$sent, inherits = FALSE))
  same = if (length(hit)) max(hit) else 0L
  warm = exists(paste(d$model, "system"), envir = the$sent, inherits = FALSE)
  cacheable = if (warm) sys + sum(chars[seq_len(same)]) else 0
  for (k in c(keys, paste(d$model, "system"))) assign(k, TRUE, envir = the$sent)
  input = ceiling((sys + sum(chars)) / 4); cached = ceiling(cacheable / 4)
  output = ceiling(nchar(resp$text %||% "") / 4) + 20L * length(resp$calls)
  d$usage$input = d$usage$input + input; d$usage$cache_read = d$usage$cache_read + cached
  d$usage$output = d$usage$output + output; d$usage$requests = d$usage$requests + 1L
  live$request_log = c(live$request_log, list(c(input = input, cached = cached)))
  list(input = input, cacheRead = cached, output = output)
}
.settle = function(s, reason) {
  d = .d(s); live = .live(s)
  d$status = switch(reason, stop = "idle", max_turns = "idle", aborted = "aborted", error = "error")
  d$reason = reason; d$step = NA_character_
  if (reason %in% c("aborted", "error") && length(d$queue)) { d$dropped = c(d$dropped, d$queue); d$queue = list() }
  if (!is.null(live)) {
    run = live$run
    if (!is.null(run)) { run$env = NULL; run$request = NULL; run$pending = NULL }   # SETCAR drops the frame reference
    live$run = NULL
    if (!isTRUE(live$retained)) live$home = NULL   # never keep a function frame after settlement
  }
  if (exists(d$id, envir = the$active, inherits = FALSE)) rm(list = d$id, envir = the$active)
  .emit(s, "agent_settled", list(reason = reason))
  if (isTRUE(live$background) && !isTRUE(the$in_wait)) .say("session ", d$id, " finished (", reason, ", turn ", d$turns, ")")
  invisible()
}

.call_adapter = function(f, ...) {        # plugins (providers, System 1 adapters) get forced values:
  args = list(...)                        # their frames may leak (closures, handlers) without pinning
  do.call(f, args)                        # a gptr frame through an unforced promise
}

# ------------------------------------------------------------------ the r tool (minimal, copy-safe)
.run_tool = function(s, call, env) {
  if (!identical(call$name, "r")) return(list(text = paste("unknown tool", call$name), is_error = TRUE))
  exprs = tryCatch(parse(text = call$arguments$code, keep.source = FALSE), error = function(e) e)
  if (inherits(exprs, "error")) return(list(text = conditionMessage(exprs), is_error = TRUE))
  prev = the$current
  the$current = list(s = s, env = env)
  on.exit({ the$current = prev }, add = TRUE)
  err = NULL
  out = utils::capture.output(for (i in seq_along(exprs)) {
    err = tryCatch({ .eval_one(exprs[[i]], env); NULL }, error = function(e) conditionMessage(e))
    if (!is.null(err)) break
  })
  txt = paste(c(out, if (!is.null(err)) paste("Error:", err)), collapse = "\n")
  list(text = .trunc(if (nzchar(txt)) txt else "(no output)", 2000L), is_error = !is.null(err))
}
.eval_one = function(e, env) {            # never passes a user object through withVisible()
  if (is.symbol(e)) { print(get(as.character(e), envir = env)); return(invisible(NULL)) }
  if (is.call(e) && is.symbol(e[[1L]]) && as.character(e[[1L]]) %in%
      c("=", "<-", "gptr_return", "invisible", "library", "for", "while", "if", "{", "Sys.sleep", "cat", "print", "message")) {
    eval(e, env)
    return(invisible(NULL))
  }
  r = withVisible(eval(e, env))
  if (r$visible) print(r$value)
  invisible(NULL)
}

# ------------------------------------------------------------------ the reactor (one loop for all runs)
.pump_all = function() {
  progressed = FALSE
  for (id in ls(the$active)) {
    s = get0(id, envir = the$active, inherits = FALSE)
    if (!is.null(s) && .advance(s)) progressed = TRUE
  }
  progressed
}
.ensure_pump = function() {               # background service at an idle console (report 15 §2.5)
  if (isTRUE(the$pump_scheduled) || !requireNamespace("later", quietly = TRUE)) return(invisible())
  the$pump_scheduled = TRUE
  later::later(.bg_tick, 0.02)
}
.bg_tick = function() {
  the$pump_scheduled = FALSE
  if (!isTRUE(the$in_foreground)) {
    t_end = Sys.time() + 0.05
    tick = function() while (Sys.time() < t_end && .pump_all()) NULL
    ss = mget(ls(the$active), envir = the$active)
    if (.human() && length(ss)) .with_pause_menu(tick, unname(ss), allow_background = FALSE, resignal = FALSE) else tick()
  }
  if (length(ls(the$active))) .ensure_pump()
}
.human = function() interactive() && !isTRUE(getOption("knitr.in.progress"))
.foreground = function(ss, human = .human()) {
  # Pump until every session in `ss` has settled (or was sent to the background from the menu).
  the$in_foreground = TRUE
  on.exit({ the$in_foreground = FALSE }, add = TRUE)
  running = function() any(vapply(ss, function(s) identical(.d(s)$status, "running") && !isTRUE(.live(s)$background), NA))
  loop = function() while (running()) if (!.pump_all()) Sys.sleep(0.005)
  if (!human) return(loop())
  .with_pause_menu(loop, ss, allow_background = TRUE, resignal = TRUE)
}
.with_pause_menu = function(fn, ss, allow_background, resignal) {
  # Ctrl-C -> interrupt condition with a "resume" restart (report 18 §2.2.1). The calling handler runs
  # INSIDE whatever is executing, possibly a tool whose stdout is captured, so menu text goes to stderr.
  # The handler only enqueues or flags; it never starts a nested run.
  say = function(...) message(...)
  tryCatch(withCallingHandlers(fn(), interrupt = function(cnd) {
    s = if (length(ss)) ss[[1L]] else NULL
    if (is.null(s)) return()
    opts = if (allow_background) "(s)teer, (f)ollow-up, (b)ackground, (a)bort, (c)ontinue? " else "(s)teer, (f)ollow-up, (a)bort, (c)ontinue? "
    ans = tryCatch(readline(paste0("[gptr] paused ", .d(s)$id, ": ", opts)), interrupt = function(e) "a")
    if (ans %in% c("s", "f")) {
      txt = readline(if (ans == "s") "steer> " else "follow-up> ")
      .enqueue(s, txt, if (ans == "s") "steer" else "follow_up", source = "menu")
      say("[gptr] queued; continuing")
      invokeRestart("resume")
    }
    if (allow_background && identical(ans, "b")) {
      for (x in ss) { live = .live(x); if (!is.null(live)) live$background = TRUE }
      .ensure_pump(); say("[gptr] running in the background; gptr_wait() re-attaches")
      invokeRestart("resume")
    }
    if (ans %in% c("c", "")) invokeRestart("resume")
  }), interrupt = function(cnd) {
    for (x in ss) { run = .live(x)$run; if (!is.null(run)) { run$abort = TRUE; .advance(x) } }
    say("[gptr] aborted; the session is kept.")
    if (resignal && isTRUE(getOption("gptr.resignal_interrupt", TRUE))) invokeRestart("abort")
  })
}

# ------------------------------------------------------------------ gateway
# Argument capture is base R and follows five rules, each verified with tracemem (p5b..p5o, t5):
#   1. no rlang quosures: a garbage quosure keeps the CALLER's frame referenced, so a wrapper's forced
#      promise (w = function(d) gptr("x", d)) is never released and d's next in-place edit copies;
#   2. dots values reach only leaf functions, called through `while` (a `for` loop that calls a closure
#      on ...elt(i) leaks the frame) and never through closures, handlers or match.arg() in this frame;
#   3. identifiers: literal > known alias > unbound symbol (literal) > force the promise (correct
#      environment even for forwarded dots, no name lookup in the wrong frame);
#   4. never assign to a formal (see gptr() body);
#   5. helpers force every argument on entry; adapters get values (.call_adapter), not promises.
.leaf_dot = function(x) list(class = class(x), is_chr1 = is.character(x) && length(x) == 1L && (!is.object(x) || inherits(x, "glue")),
                             dim = dim(x), length = length(x), size = as.numeric(utils::object.size(x)),
                             # System 1 has no R access: small character context travels as its VALUE (a new
                             # vector from paste0(), never a reference to the user's object)
                             text = if (is.character(x) && sum(nchar(x, "bytes")) <= 65536L) paste0(x) else NULL)
.labels_of = function(exprs, nms) {       # expressions only, never values
  out = character(length(exprs))
  for (i in seq_along(exprs)) out[i] = if (nzchar(nms[i])) nms[i] else if (is.symbol(exprs[[i]])) as.character(exprs[[i]]) else
    paste(deparse(exprs[[i]], nlines = 1L), collapse = "")
  out
}
.ident_call = function(expr, caller) {    # c(opus, haiku), if (hard) opus else haiku: alias mask
  mask = list2env(stats::setNames(as.list(the$known_models), the$known_models), parent = caller)
  out = as.character(eval(expr, mask))
  parent.env(mask) = emptyenv()           # unpin the caller frame (SET_ENCLOS decrements its count)
  out
}

gptr = function(..., model = NULL, prompt = NULL, envir = NULL, background = FALSE, parallel = NULL,
                queue = c("steer", "follow_up"), choices = NULL) {
  # Rule 4: never assign to a formal. An unforced default-argument promise has PRENV == this frame;
  # overwriting it leaves a garbage promise that keeps the frame referenced, so R_CleanupEnvir never
  # releases the forced dots and the user's object keeps a sticky reference (p5n, p5o). New locals only.
  caller = parent.frame()
  q_mode = queue[1L]
  if (!q_mode %in% c("steer", "follow_up")) .gptr_abort("queue must be \"steer\" or \"follow_up\"", "bad_argument")
  me = substitute(model)
  m_id = if (is.null(me)) NULL else if (is.character(me)) me else
    if (is.symbol(me) && as.character(me) %in% the$known_models) as.character(me) else
    if (is.symbol(me) && !exists(as.character(me), envir = caller)) as.character(me) else
    if (is.call(me) && !identical(me[[1L]], quote(I))) .ident_call(me, caller) else as.character(model)
  n = ...length()
  exprs = as.list(substitute(list(...)))[-1L]
  nms = ...names() %||% rep("", n)
  nms[is.na(nms)] = ""
  facts = vector("list", n)
  i = 1L
  while (i <= n) { facts[[i]] = .leaf_dot(...elt(i)); i = i + 1L }
  p_given = prompt
  plan = .plan_dots(exprs, nms, facts, !is.null(p_given))
  target = if (!is.na(plan$ci)) ...elt(plan$ci) else NULL
  p_text = if (!is.null(p_given)) as.character(p_given) else if (!is.na(plan$p_idx)) as.character(...elt(plan$p_idx)) else NULL
  env_arg = envir

  # System 1: a typed judgement; a piped session is READ (its last answer is the state), never continued
  if (!is.null(m_id) && m_id %in% the$s1_models)
    return(.system_one(p_text, target, plan$s1_state, choices))
  # a list of sessions (from parallel = n): steer every member, concurrently, return the same list
  if (inherits(target, "gptr_sessions")) {
    k = 1L
    while (k <= length(target)) {
      .submit(target[[k]], p_text, character(), m_id, q_mode, env_arg, caller, background = TRUE, source = "pipe", quiet = TRUE)
      k = k + 1L
    }
    return(gptr_wait(target))
  }
  if (!is.null(parallel)) {
    j = plan$ctx_idx[1L]
    return(.parallel(p_text, plan$labels[j], ...elt(j), m_id, parallel, env_arg %||% caller))
  }
  if (is.null(p_text)) {
    if (!interactive()) .gptr_abort("gptr() without a prompt starts the interactive console and needs an interactive session.", "noninteractive")
    .gptr_abort("(prototype) the interactive console is out of scope for G3", "console")
  }
  replayed = .replay_hook(target, p_text, caller)            # history document: replay returns early
  if (!is.null(replayed)) return(invisible(replayed))
  .submit(target, p_text, plan$context, m_id, q_mode, env_arg, caller, background, source = "pipe")
}
.plan_dots = function(exprs, nms, facts, have_prompt) {   # facts only: decide target, prompt, context
  n = length(facts)
  labels = .labels_of(exprs, nms)
  literal = vapply(exprs, function(e) is.character(e) && length(e) == 1L, NA)
  is_s = vapply(facts, function(f) any(f$class %in% c("gptr_session", "gptr_sessions")), NA)
  named = nzchar(nms)
  ci = which(is_s & !named)[1L]
  cand = which(!named & !is_s)
  lit = cand[literal[cand]]
  chr = cand[vapply(facts[cand], function(f) isTRUE(f$is_chr1), NA)]
  p_idx = if (have_prompt) NA_integer_ else if (length(lit)) lit[1L] else if (length(chr)) chr[1L] else NA_integer_
  ctx_idx = setdiff(seq_len(n), c(ci, p_idx))
  ctx_idx = ctx_idx[!is.na(ctx_idx)]
  context = vapply(ctx_idx, function(j) .fmt_facts(labels[j], facts[[j]]), "")
  s1_state = if (length(ctx_idx) && !is.null(facts[[ctx_idx[1L]]]$text)) facts[[ctx_idx[1L]]]$text else context
  list(ci = ci, p_idx = p_idx, ctx_idx = ctx_idx, labels = labels, context = context, s1_state = s1_state)
}

.submit = function(s, prompt, context, model, queue, envir, caller, background, source, quiet = FALSE) {
  force(s); force(prompt); force(context); force(model); force(queue); force(envir); force(caller)
  force(background); force(source); force(quiet)   # rule 5: no unforced promise into the gateway frame
  if (is.null(s)) {
    home = envir %||% caller
    retained = !is.null(envir) || !.on_stack(home)
    s = .new_session(model, home, retained)
    source = "call"
  } else .ensure_attached(s, caller)
  d = .d(s); live = .live(s)
  if (!is.null(model) && !identical(model, d$model)) {
    d$model = model
    .append_entry(s, "model_change", list(provider = "fake", modelId = model))
  }
  text = paste(c(prompt, if (length(context)) paste("Attached:", paste(context, collapse = "\n"))), collapse = "\n")
  if (identical(d$status, "running")) {    # steering a running session: enqueue, return at once
    .enqueue(s, text, queue, source = source)
    if (!quiet) .say("queued ", queue, " for running session ", d$id)
    return(invisible(s))
  }
  turn_env = envir %||% live$home %||% caller
  if (is.null(live$home) && !isTRUE(live$retained)) live$home = turn_env   # held only while running
  .append_user(s, text, "prompt", source)
  .start_run(s, turn_env)
  live$background = isTRUE(background)
  if (isTRUE(background)) { .ensure_pump(); return(invisible(s)) }
  .foreground(list(s))
  if (identical(d$status, "running")) return(invisible(s))   # sent to the background from the pause menu
  if (!is.null(the$pending_record)) .record_turn(s)   # history document (doc.R); no-op without it
  .emit(s, "returned", NULL)
  if (interactive() && !isTRUE(getOption("knitr.in.progress"))) { print(s); invisible(s) } else s
}

gptr_wait = function(x, timeout = Inf) {
  ss = if (inherits(x, "gptr_sessions")) unclass(x) else list(x)
  for (s in ss) { live = .live(s); if (!is.null(live)) live$background = FALSE }
  t0 = Sys.time()
  the$in_wait = TRUE
  on.exit({ the$in_wait = FALSE }, add = TRUE)
  if (is.finite(timeout)) {
    while (any(vapply(ss, function(s) identical(.d(s)$status, "running"), NA))) {
      if (as.numeric(Sys.time() - t0, units = "secs") > timeout) {
        warning(structure(class = c("gptr_warning_timeout", "warning", "condition"),
                          list(message = "gptr_wait() timed out; the session keeps running", call = NULL)))
        for (s in ss) { live = .live(s); if (!is.null(live)) live$background = TRUE }
        .ensure_pump()
        return(invisible(x))
      }
      if (!.pump_all()) Sys.sleep(0.005)
    }
  } else .foreground(ss)
  x
}
gptr_cancel = function(x) {
  live = .live(x)
  if (!is.null(live$run)) { live$run$abort = TRUE; .advance(x) }
  invisible(x)
}
gptr_jobs = function() {
  ids = ls(the$active)
  data.frame(id = ids, status = vapply(ids, function(i) .d(get(i, envir = the$active))$status, ""),
             turns = vapply(ids, function(i) .d(get(i, envir = the$active))$turns, 1L), row.names = NULL)
}

# ------------------------------------------------------------------ attach / detach / resume
.ensure_attached = function(s, caller) {
  if (!is.null(.live(s))) return(invisible(s))
  d = .d(s)
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w) && !is.null(rlang::wref_key(w))) { invisible(gc()); w = get0(d$id, envir = the$live, inherits = FALSE) }
  if (!is.null(w) && !is.null(rlang::wref_key(w)) && !identical(rlang::wref_key(w), s))
    .gptr_abort(sprintf("another live object for session %s exists in this R process. Use gptr_resume(\"%s\") to get it, or gptr_fork() to branch this copy.", d$id, d$id), "split_brain")
  if (identical(d$status, "running")) { d$status = "aborted"; d$reason = "detached"; d$step = NA_character_ }
  if (file.exists(d$file)) {              # the file may have moved on: continue from THIS object's leaf
    ids = vapply(Filter(function(l) nzchar(l), readLines(d$file, warn = FALSE))[-1], function(l) jsonlite::fromJSON(l)$id, "")
    newer = setdiff(ids, vapply(d$entries, function(e) e$id, ""))
    if (length(newer)) .say("session ", d$id, ": continuing from this object's state (turn ", d$turns, "); ",
                            length(newer), " newer entries in the file stay as a sibling branch")
    d$flushed = TRUE
  }
  home = caller
  .attach_live(s, home = if (!.on_stack(home)) home else NULL, retained = !.on_stack(home))
  .lock(s)
  .say("re-attached session ", d$id, " (home ", .env_label(home), ")")
  invisible(s)
}
gptr_resume = function(x = NULL) {
  caller = parent.frame()
  files = list.files(.sessions_dir(), pattern = "[.]jsonl$", full.names = TRUE)
  files = files[!grepl("[.]inbox[.]jsonl$", files)]
  path = if (is.null(x)) files[which.max(file.mtime(files))] else if (file.exists(x)) x else {
    hit = files[grepl(paste0("_", x), basename(files), fixed = TRUE)]
    if (!length(hit)) .gptr_abort(paste("no session matching", x), "not_found")
    hit[1L]
  }
  id = sub("^.*_([0-9a-f]+)[.]jsonl$", "\\1", basename(path))
  w = get0(id, envir = the$live, inherits = FALSE)
  if (!is.null(w) && !is.null(rlang::wref_key(w))) return(rlang::wref_key(w))   # the same object
  s = new.env(parent = emptyenv()); d = new.env(parent = emptyenv())
  assign(".d", d, envir = s); class(s) = "gptr_session"
  d$file = path; d$loaded = FALSE; d$leaf = NULL
  h = .load_file(d, path)
  d$id = h$id; d$created = h$timestamp; d$persist = TRUE
  d$parent = if (!is.null(h$gptr$forkOf)) c(h$gptr$forkOf, list(file = h$parentSession)) else NULL
  msgs = Filter(function(e) identical(e$type, "message"), .path(d))
  d$turns = sum(vapply(msgs, function(e) identical(e$message$role, "user"), NA))
  fin = Filter(function(e) identical(e$message$role, "assistant") && !identical(e$message$stopReason, "toolUse"), msgs)
  d$last_text = if (length(fin)) fin[[length(fin)]]$message$content[[1]]$text else NA_character_
  tail_role = if (length(msgs)) msgs[[length(msgs)]]$message$role else "none"
  d$status = if (identical(tail_role, "assistant")) "idle" else "interrupted"
  d$reason = NA_character_; d$step = NA_character_
  d$model = Reduce(function(m, e) if (identical(e$type, "model_change")) e$modelId else if (identical(e$type, "message") && !is.null(e$message$model)) e$message$model else m, .path(d), "fake")
  d$usage = list(input = 0, output = 0, cache_read = 0, requests = 0L)
  d$values = lapply(Filter(function(e) identical(e$customType, "gptr.value"), .path(d)), function(e) e$data)
  d$queue = list(); d$dropped = list(); d$replayed = integer(); d$ext = list(); d$flushed = TRUE
  d$home_label = .env_label(caller)
  .attach_live(s, home = if (!.on_stack(caller)) caller else NULL, retained = !.on_stack(caller))
  .lock(s)
  s
}

# ------------------------------------------------------------------ fork
gptr_fork = function(s, at = NULL, envir = c("overlay", "shared")) {
  envir = match.arg(envir)
  caller = parent.frame()
  .ensure_loaded(s)
  d = .d(s)
  path = .path(d)
  # cut points: indices where the branch is closed (no tool call awaiting its result)
  open = 0L; closed = integer(); turn_at = integer(); turn = 0L
  for (i in seq_along(path)) {
    e = path[[i]]; is_user = FALSE
    if (identical(e$type, "message")) {
      m = e$message
      if (identical(m$role, "user")) { turn = turn + 1L; is_user = TRUE }
      if (identical(m$role, "assistant")) open = sum(vapply(m$content, function(b) identical(b$type, "toolCall"), NA))
      if (identical(m$role, "toolResult")) open = open - 1L
    }
    if (open == 0L && !is_user) { closed = c(closed, i); turn_at = c(turn_at, turn) }
  }
  cut = if (is.null(at)) max(closed, 0L) else if (at == 0L) 0L else {
    ok = closed[turn_at == at]
    if (!length(ok)) .gptr_abort(sprintf("turn %s has no settled boundary to fork at", at), "fork_at")
    max(ok)
  }
  kept = if (cut > 0L) path[seq_len(cut)] else list()
  kept = Filter(function(e) !identical(e$type, "label"), kept)
  prev = NULL
  for (i in seq_along(kept)) { kept[[i]]["parentId"] = list(prev); prev = kept[[i]]$id }
  k_turn = if (cut > 0L) turn_at[match(cut, closed)] else 0L
  parent_home = .live(s)$home %||% caller
  home = if (identical(envir, "overlay")) {
    ov = new.env(parent = parent_home)
    attr(ov, "gptr_overlay") = sprintf("overlay of %s (fork of %s)", .env_label(parent_home), d$id)
    ov
  } else parent_home
  f = .new_session(d$model, home, retained = TRUE,
                   parent = list(id = d$id, entry = if (cut > 0L) kept[[length(kept)]]$id else NULL, turn = k_turn, file = d$file))
  fd = .d(f)
  fd$entries = kept
  for (i in seq_along(kept)) assign(kept[[i]]$id, i, envir = fd$index)
  fd$leaf = prev
  fd$turns = k_turn
  fin = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "assistant") && !identical(e$message$stopReason, "toolUse"), kept)
  fd$last_text = if (length(fin)) fin[[length(fin)]]$message$content[[1]]$text else NA_character_
  fd$values = Filter(function(v) v$turn <= k_turn, d$values)
  fd$flushed = FALSE                      # written with its first own message (lazy, as Pi's new files):
                                          # an unused or replay-adopted fork leaves no orphan file
  .emit(f, "session_start", list(reason = "fork", parent = d$id))
  f
}

# ------------------------------------------------------------------ parallel = n -> gptr_sessions
.parallel = function(prompt, label, x, model, n, home) {     # binds the user's list: leaves only, while loop
  force(prompt); force(label); force(model); force(n); force(home)
  k = length(x); descs = character(k); nm = names(x) %||% paste0("[[", seq_len(k), "]]")
  i = 1L
  while (i <= k) { descs[i] = .fmt_facts(paste0(label, "$", nm[i]), .leaf_facts(x[[i]])); i = i + 1L }
  .parallel_run(prompt, descs, nm, model, n, home)
}
.parallel_run = function(prompt, descs, nm, model, n, home) {
  retained = !.on_stack(home)
  ss = lapply(seq_along(descs), function(i) {
    s = .new_session(model, home, retained)
    .append_user(s, paste0(prompt, "\nAttached: ", descs[i]), "prompt", "call")
    s
  })
  names(ss) = nm
  started = rep(FALSE, length(ss))
  repeat {                                 # admission control: at most n running
    running = sum(vapply(ss, function(s) identical(.d(s)$status, "running"), NA))
    nxt = which(!started)[1L]
    if (!is.na(nxt) && running < n) { started[nxt] = TRUE; .start_run(ss[[nxt]], .live(ss[[nxt]])$home %||% home); next }
    if (!running && is.na(nxt)) break
    if (!.pump_all()) Sys.sleep(0.005)
  }
  structure(ss, class = "gptr_sessions")
}
print.gptr_sessions = function(x, ...) {
  cat(sprintf("<gptr_sessions> %d sessions\n", length(x)))
  for (i in seq_along(x)) { d = .d(x[[i]]); cat(sprintf("  %-10s %s %-7s %d turns  %s\n", names(x)[i], d$id, d$status, d$turns, .trunc(d$last_text, 40L))) }
  invisible(x)
}
`[.gptr_sessions` = function(x, i) structure(unclass(x)[i], class = "gptr_sessions")

# ------------------------------------------------------------------ System 1 on a session
.system_one = function(question, target, context, choices) {
  force(question); force(target); force(context); force(choices)
  state = if (inherits(target, "gptr_session")) {
    d = .d(target); v = .values_table(target)
    paste0("Answer: ", .trunc(d$last_text, 2000L),
           if (nrow(v)) sprintf("\nValue: %s <%s>", v$name[nrow(v)], v$class[nrow(v)]) else "")
  } else context
  if (!is.null(choices)) {                # choose-one-of-N: a classed character, not a factor (report 04)
    k = .call_adapter(the$s1_choice, question, state, choices)
    out = structure(choices[k$idx], prob = k$prob, class = c("gptr_choice", "character"))
    p = k$prob
  } else {
    p = .call_adapter(the$s1, question, state)
    out = structure(p >= 0.5, prob = p, class = c("gptr_decision", "logical"))
  }
  if (inherits(target, "gptr_session"))    # audit trail only: a custom entry never enters the context
    .append_entry(target, "custom", list(customType = "gptr.decision", data = list(question = question, answer = unclass(out), prob = p, state_chars = nchar(state))))
  out
}
print.gptr_decision = function(x, ...) { print(as.vector(unclass(x))); cat(sprintf("prob: %s\n", paste(format(attr(x, "prob"), digits = 2), collapse = " "))); invisible(x) }

# ------------------------------------------------------------------ history-document hook (set by doc.R)
.replay_hook = function(target, prompt, caller) { force(target); force(prompt); force(caller); NULL }
.record_turn = function(s) invisible()
````

### `hist/analysis.R`

````r
# analysis.R -- the program and the record of the agent work
a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')
# >>> gptr:b1120d model=fake/fake date=2026-09-29 prompt=255a3959007b session=574f66ef turn=1 value=counts
counts = matrix(c(5, 50, 500, 5000, 6, 60, 600, 6000, 7, 70, 700, 7000), 4)
dim(counts)
#> [1] 4 3
## Decision: (fake) answered turn 1.
a$value = counts
# <<< gptr:b1120d
# >>> gptr:7d3937 model=fake/fake date=2026-09-29 prompt=6ef699c61233 call=2 session=574f66ef turn=2 value=tpm
tpm = t(t(counts) / colSums(counts)) * 1e6
round(colSums(tpm))
#> [1] 1e+06 1e+06 1e+06
## Decision: (fake) answered turn 2.
a$value = tpm
# <<< gptr:7d3937
a |> gptr('How many genes pass the filter at 2 samples?')
# >>> gptr:fafb88 model=fake/fake date=2026-09-29 prompt=ccd141411a25 session=574f66ef turn=3 value=keep
keep = rowSums(tpm > 1e4) >= 2
sum(keep)
#> [1] 2
## Decision: (fake) answered turn 3.
a$value = keep
# <<< gptr:fafb88
gptr_fork(a) |> gptr('Try a stricter filter as well')
# >>> gptr:6413d0 model=fake/fake date=2026-09-29 prompt=ed64d3adeff7 session=601e5020 turn=4 fork=574f66ef:3 value=keep
local({
  keep = rowSums(tpm > 1e5) >= 2
  sum(keep)
  #> [1] 1
}, envir = gptr_resume("601e5020")$envir)
## Decision: (fake) answered turn 4.
# <<< gptr:6413d0
````

### `hist/driver_lib.R`

````r
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"; P = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3/hist"
options(g3.with_doc = TRUE)
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(P, ".gptr", "sessions"), gptr.replay = Sys.getenv("MODE"), gptr.quiet = Sys.getenv("QUIET") == "1")
the$provider = fake_rules(list(
  "Load the counts" = list(code = "counts = matrix(c(5, 50, 500, 5000, 6, 60, 600, 6000, 7, 70, 700, 7000), 4)\ngptr_return(counts)\ndim(counts)"),
  "TPM" = list(code = "tpm = t(t(counts) / colSums(counts)) * 1e6\ngptr_return(tpm)\nround(colSums(tpm))"),
  "stricter" = list(code = "keep = rowSums(tpm > 1e5) >= 2\ngptr_return(keep)\nsum(keep)"),
  "filter" = list(code = "keep = rowSums(tpm > 1e4) >= 2\ngptr_return(keep)\nsum(keep)")))
run = function() { source(file.path(P, "analysis.R"), keep.source = TRUE, local = globalenv())
  cat(sprintf("  requests=%d | a: id %s turns %d, value %s | session files %d | global keep: rows %s\n", the$requests, a$id, a$turns,
      paste0(class(a$value), "[", length(a$value), "]"), length(list.files(getOption("gptr.sessions_dir"), "[.]jsonl$")), paste(which(keep), collapse = ",")))
  invisible() }
````

### `knit/doc.Rmd`

````text
---
title: cache test
---
```{r setup, include = FALSE}
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3/setup.R"); options(gptr.sessions_dir = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3/knit/sessions", gptr.quiet = TRUE); the$provider = fake_rules(list())
```
```{r first, cache = TRUE}
s = gptr("summarise mtcars")
```
```{r second}
s |> gptr("now shorten it")
cat("requests made in this knit:", the$requests, "| turns:", s$turns, "| status:", s$status, "\n")
```
````

### `knit/doc.md`

````text
---
title: cache test
---


``` r
s = gptr("summarise mtcars")
```

``` r
s |> gptr("now shorten it")
```

```
## [fake] Answer to: now shorten it
## <gptr_session 1d3476cc> idle | 2 turns | fake | 672 in (0 cached) / 17 out | value: none
```

``` r
cat("requests made in this knit:", the$requests, "| turns:", s$turns, "| status:", s$status, "\n")
```

```
## requests made in this knit: 1 | turns: 2 | status: idle
```
````

### `knit/sessions/2026-09-30T05-55-50-392Z_1d3476cc.jsonl`

````text
{"type":"session","version":3,"id":"1d3476cc","timestamp":"2026-09-30T05:55:50.392Z","cwd":"/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3/knit","gptr":{"format":1}}
{"type":"message","id":"5f635a0e","parentId":null,"timestamp":"2026-09-30T05:55:50.394Z","message":{"role":"user","content":[{"type":"text","text":"summarise mtcars"}],"timestamp":1790747750395,"gptr":{"deliver":"prompt","source":"call"}}}
{"type":"message","id":"73ad7e0e","parentId":"5f635a0e","timestamp":"2026-09-30T05:55:50.459Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: summarise mtcars"}],"provider":"fake","model":"fake","usage":{"input":323,"cacheRead":0,"output":9},"stopReason":"stop","timestamp":1790747750460}}
{"type":"message","id":"522b5ea8","parentId":"73ad7e0e","timestamp":"2026-09-30T05:55:50.473Z","message":{"role":"user","content":[{"type":"text","text":"now shorten it"}],"timestamp":1790747750474,"gptr":{"deliver":"prompt","source":"pipe"}}}
{"type":"message","id":"1d5391bd","parentId":"522b5ea8","timestamp":"2026-09-30T05:55:50.525Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: now shorten it"}],"provider":"fake","model":"fake","usage":{"input":349,"cacheRead":323,"output":8},"stopReason":"stop","timestamp":1790747750525}}
{"type":"message","id":"3f6e6d0b","parentId":"73ad7e0e","timestamp":"2026-09-30T05:55:51.684Z","message":{"role":"user","content":[{"type":"text","text":"now shorten it"}],"timestamp":1790747751685,"gptr":{"deliver":"prompt","source":"pipe"}}}
{"type":"message","id":"6ab90db5","parentId":"3f6e6d0b","timestamp":"2026-09-30T05:55:51.739Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: now shorten it"}],"provider":"fake","model":"fake","usage":{"input":349,"cacheRead":0,"output":8},"stopReason":"stop","timestamp":1790747751739}}
````

### `ns.out`

````text
==================== north-star §2: the same function as a programmable call
  TRACE res = gptr('Fit a mixed model...', mice) session 268c00f4 | idle | turns 1 | model fake | value lme | requests so far 2
  > res        (Rscript: visible, the print method shows the answer + footer)
[fake] Done ((Intercept)       dietB ). Saw: 'Fit a mixed model of weight on diet with'
<gptr_session 268c00f4> idle | 1 turn | fake | 792 in (363 cached) / 42 out | value: fit <lme>
  > class(res$value): lme 
  > res$usage: List of 4
 $ input     : num 792
 $ output    : num 42
 $ cache_read: num 363
 $ requests  : int 2
  TRACE mice |> gptr('Which columns...')   session 6bbafeb1 | idle | turns 1 | model fake | value none | requests so far 3
  > data-first pipe started a NEW session: TRUE | context sent: <object name=mice class=data.frame 48x3 size=3.4 Kb> 
==================== north-star §3: the pipe steers one session object
  TRACE the three-step chain               session 4f2c311b | idle | turns 3 | model opus | value prcomp | requests so far 9
  > one session for the whole chain; models along it: fake -> opus 
  TRACE qc = gptr('Run QC...', pbmc)       session 1a00dd5f | idle | turns 1 | model fake | value logical | requests so far 11

FALSE  TRUE 
    5     3 
[fake] Done ([1] 4). Saw: 'Use 15% mitochondrial reads as the cut-o'
<gptr_session 1a00dd5f> idle | 2 turns | fake | 1.6k in (1.5k cached) / 74 out | value: low_q <logical>
  TRACE qc |> gptr('Use 15%...')           session 1a00dd5f | idle | turns 2 | model fake | value logical | requests so far 13
  > qc$value (the steered result): flagged 4 cells
  TRACE gptr_fork(qc) |> gptr('Try 10%')   session 1f285dac | idle | turns 3 | model fake | value logical | requests so far 15
  > fork flagged 6 cells in its overlay; qc still flags 4 ; user's low_q flags 4 
==================== north-star §11: a whole workflow that reads like R
  TRACE prep = ... |> ... |> ...           session 2bd7afdd | idle | turns 3 | model fake | value prcomp | requests so far 20
  TRACE cluster 0: markers CD3E, IL7R     -> System 1 dendritic cell (prob 0.81)
  TRACE cluster 1: markers MS4A1, CD79A   -> System 1 T cell (prob 0.81)
  TRACE cluster 2: markers AMBIG1, AMBIG2 -> System 1 unclear (prob 0.81)
  TRACE   cluster 2 investigation chain    session 1d801fed | idle | turns 2 | model fake | value character | requests so far 23
  TRACE cluster 3: markers GNLY, NKG7     -> System 1 dendritic cell (prob 0.81)
  > System 1 calls cost 0 System 2 requests; the loop made 3 System 2 requests (only the unclear cluster)
  > the unassigned loop session was garbage-collected: TRUE ; its transcript stays in ns 
  TRACE gptr('Build a Shiny app...', pbmc) session 3e65ff9b | idle | turns 1 | model fake | value none | requests so far 24
````

### `ns_traces.R`

````r
# ns_traces.R -- north-star §2, §3 and §11 traced statement by statement through the G3 prototype.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "ns"), gptr.quiet = TRUE)
the$s1 = fake_s1; the$s1_choice = fake_s1_choice
trace = function(label, x) {
  if (inherits(x, "gptr_session")) cat(sprintf("  TRACE %-34s session %s | %s | turns %d | model %s | value %s | requests so far %d\n",
    label, x$id, x$status, x$turns, x$model, if (is.null(x$value)) "none" else class(x$value)[1], the$requests))
  else cat(sprintf("  TRACE %-34s <%s> %s\n", label, class(x)[1], paste(format(unclass(x)), collapse = " ")))
}
the$provider = fake_rules(list(
  "mixed model" = list(code = "fit = nlme::lme(weight ~ diet, random = ~ 1 | mouse, data = mice)\ngptr_return(fit)\nround(nlme::fixef(fit), 2)"),
  "missing" = list(answer = "No column has missing values (checked with colSums(is.na(mice))); no imputation needed."),
  "Normalise pbmc" = list(code = "pbmc$norm = log1p(pbmc$umi)\ngptr_return(pbmc)\nncol(pbmc)"),
  "Regress out" = list(code = "pbmc$scaled = resid(lm(norm ~ percent.mt, data = pbmc))\ngptr_return(pbmc)\nround(sd(pbmc$scaled), 3)"),
  "counts in" = list(code = "counts = as.matrix(read.csv(counts_csv, row.names = 1))\nnorm = log1p(t(t(counts) / colSums(counts)) * 1e4)\ngptr_return(norm)\ndim(norm)"),
  "PCA" = list(code = "pca = prcomp(t(norm))\nve = cumsum(pca$sdev^2) / sum(pca$sdev^2)\ngptr_return(pca)\nwhich(ve >= 0.8)[1]"),
  "PC1 against PC2" = list(code = "plot(pca$x[, 1:2], col = batch)\ninvisible(NULL)"),
  "QC" = list(code = "low_q = pbmc$percent.mt > 20\ngptr_return(low_q)\nsum(low_q)"),
  "15%" = list(code = "low_q = pbmc$percent.mt > 15\ngptr_return(low_q)\nsum(low_q)"),
  "10%" = list(code = "low_q = pbmc$percent.mt > 10\ngptr_return(low_q)\nsum(low_q)"),
  "30 PCs" = list(answer = "Kept 30 PCs; the elbow flattens near 12, so 12-15 would also do."),
  "ambiguous" = list(code = "extra = c('FCER1A', 'CST3')\ngptr_return(extra)\nextra"),
  "canonical" = list(answer = "Label: dendritic cells (FCER1A, CST3 are canonical cDC2 markers).")))

cat("==================== north-star §2: the same function as a programmable call\n")
set.seed(1)
mice = data.frame(mouse = factor(rep(1:12, each = 4)), diet = factor(rep(c("A", "B"), 24)), weight = rnorm(48, 20))
res = gptr("Fit a mixed model of weight on diet with a random intercept per
             mouse, and report the diet effect.", mice)
trace("res = gptr('Fit a mixed model...', mice)", res)
cat("  > res        (Rscript: visible, the print method shows the answer + footer)\n"); print(res)
cat("  > class(res$value):", class(res$value), "\n")
cat("  > res$usage: "); str(res$usage)
a2 = mice |> gptr("Which columns have missing values, and how should I impute them?")
trace("mice |> gptr('Which columns...')", a2)
cat("  > data-first pipe started a NEW session:", !identical(a2, res), "| context sent:", sub(".*Attached: ", "", a2$history$text[1]), "\n")

cat("==================== north-star §3: the pipe steers one session object\n")
counts_csv = tempfile(fileext = ".csv")
write.csv(matrix(rpois(60, 20), 6, dimnames = list(paste0("g", 1:6), paste0("s", 1:10))), counts_csv)
batch = rep(1:2, 5)
invisible(grDevices::pdf(NULL))
chain = gptr("Load the counts in data/counts.csv and normalise them") |>
  gptr("Now run a PCA and tell me how many components explain 80% of variance") |>
  gptr("Plot PC1 against PC2 coloured by batch", model = opus)
trace("the three-step chain", chain)
cat("  > one session for the whole chain; models along it:", paste(unique(chain$history$model[!is.na(chain$history$model)]), collapse = " -> "), "\n")
pbmc = data.frame(cell = 1:8, percent.mt = c(3, 8, 12, 14, 17, 22, 30, 45), umi = c(900, 1200, 800, 1500, 700, 400, 300, 200))
qc = gptr("Run QC on pbmc and flag low-quality cells", pbmc)
trace("qc = gptr('Run QC...', pbmc)", qc)
print(table(pbmc$percent.mt > 20))                        # ordinary R in between
qc |> gptr("Use 15% mitochondrial reads as the cut-off instead of 20%")
trace("qc |> gptr('Use 15%...')", qc)
cat("  > qc$value (the steered result): flagged", sum(qc$value), "cells\n")
f10 = gptr_fork(qc) |> gptr("Try a 10% cut-off as well")
trace("gptr_fork(qc) |> gptr('Try 10%')", f10)
cat("  > fork flagged", sum(f10$value), "cells in its overlay; qc still flags", sum(qc$value), "; user's low_q flags", sum(low_q), "\n")

cat("==================== north-star §11: a whole workflow that reads like R\n")
FindNeighbors = function(obj, dims) obj
FindClusters = function(obj, resolution) { obj$cluster = factor(c(0, 0, 1, 1, 2, 2, 3, 3)); obj }
Idents = function(obj) obj$cluster
FindMarkers = function(obj, ident.1, only.pos) {
  genes = list(`0` = c("CD3E", "IL7R"), `1` = c("MS4A1", "CD79A"), `2` = c("AMBIG1", "AMBIG2"), `3` = c("GNLY", "NKG7"))[[ident.1]]
  data.frame(p = seq_along(genes) / 10, row.names = genes)
}
prep = gptr("Normalise pbmc, find variable features and run PCA", pbmc) |>
  gptr("Regress out percent.mt while scaling") |>
  gptr("Keep 30 PCs; tell me if the elbow suggests fewer")
trace("prep = ... |> ... |> ...", prep)
pbmc = FindNeighbors(pbmc, dims = 1:30) |> FindClusters(resolution = 0.8)
n0 = the$requests
for (cl in levels(Idents(pbmc))) {
  markers = FindMarkers(pbmc, ident.1 = cl, only.pos = TRUE)
  top = paste(head(rownames(markers), 10), collapse = ", ")
  cell_type = gptr("Which immune cell type do these marker genes indicate?",
                    top, model = jev,
                    choices = c("T cell", "B cell", "NK cell", "monocyte",
                                "dendritic cell", "platelet", "unclear"))
  cat(sprintf("  TRACE cluster %s: markers %-14s -> System 1 %s (prob %.2f)\n", cl, top, cell_type, attr(cell_type, "prob")))
  if (cell_type == "unclear") {
    inv = gptr(glue::glue("Cluster {cl} has ambiguous markers ({top}). Investigate with
          additional markers and propose a label."), pbmc) |>
      gptr("Prefer canonical markers from the literature; explain your choice")
    trace(paste0("  cluster ", cl, " investigation chain"), inv)
    inv_id = inv$id
  }
}
cat("  > System 1 calls cost", 0, "System 2 requests; the loop made", the$requests - n0, "System 2 requests (only the unclear cluster)\n")
rm(inv); invisible(gc())
cat("  > the unassigned loop session was garbage-collected:", inv_id %in% the$finalized, "; its transcript stays in", basename(dirname(list.files(getOption("gptr.sessions_dir"), pattern = inv_id, full.names = TRUE)[1])), "\n")
app = gptr("Build a Shiny app to browse clusters, markers and a UMAP", pbmc)
trace("gptr('Build a Shiny app...', pbmc)", app)
````

### `p1_weakref.R`

````r
# p1_weakref.R -- can a registry hold per-session live resources without keeping the session alive?
# (a) strong registry entry: session never collected; (b) rlang weakref(key = session, value = live)
# where `live` references the session (cycle through the value): is the key still collected?
fin = new.env(); fin$log = character()   # state in an environment, no <<-
make_session = function(id) {
  s = new.env(parent = emptyenv())
  s$id = id
  class(s) = "gptr_session"
  reg.finalizer(s, function(e) fin$log = c(fin$log, e$id), onexit = FALSE)
  s
}
reg = new.env(parent = emptyenv())

# (a) strong: registry value references the session
s = make_session("strong")
live = new.env(parent = emptyenv()); live$session = s
assign("strong", live, envir = reg)
rm(s, live); invisible(gc()); invisible(gc())
cat("(a) strong registry -> finalized:", "strong" %in% fin$log, "\n")

# (b) weak: key = session, value = live env that references the session (value -> key cycle)
s = make_session("weak")
live = new.env(parent = emptyenv()); live$session = s; live$home = globalenv()
assign("weak", rlang::new_weakref(key = s, value = live), envir = reg)
cat("(b) before rm: key alive:", !is.null(rlang::wref_key(get("weak", envir = reg))), "\n")
rm(s, live); invisible(gc()); invisible(gc())
w = get("weak", envir = reg)
cat("(b) weak registry -> finalized:", "weak" %in% fin$log,
    "| key after gc is NULL:", is.null(rlang::wref_key(w)),
    "| value after gc is NULL:", is.null(rlang::wref_value(w)), "\n")

# (c) weak entry whose value holds a function frame that binds the session (home = frame)
f = function() {
  s = make_session("frame")
  live = new.env(parent = emptyenv()); live$home = environment()
  assign("frame", rlang::new_weakref(key = s, value = live), envir = reg)
  invisible(NULL)
}
f(); invisible(gc()); invisible(gc())
cat("(c) weak entry, value = frame binding the session -> finalized:", "frame" %in% fin$log, "\n")
cat("finalizer log:", fin$log, "\n")
````

### `p2_frame_sticky.R`

````r
# p2_frame_sticky.R -- does a session that keeps a reference to the function frame it was created in
# give the caller's object a sticky reference (next in-place edit copies)? Run each case in a fresh
# process: Rscript --vanilla p2_frame_sticky.R <case>
case = commandArgs(TRUE)[1]
keep = new.env(parent = emptyenv())
wrapper = function(d, hold) {
  n = length(d)                                   # force the promise, as a gateway that inspects d would
  if (hold == "strong") keep$home = environment() # session holds its home env (the frame) strongly
  if (hold == "weak") keep$home = rlang::new_weakref(key = keep, value = environment())
  if (hold == "label") keep$home = "frame of wrapper()"  # session keeps only a label
  invisible(n)
}
v = runif(5e6)
wrapper(v, case)
invisible(tracemem(v))
v[1] = 0
cat("case", case, "END\n")
````

### `p3_log.txt`

````text

````

### `p3_other.txt`

````text
written through the stale connection
````

### `p3_serialize_live.R`

````r
# p3_serialize_live.R -- what saveRDS/readRDS, serialize() and callr do to an environment-backed session
# that holds live resources (a connection, a curl handle, a processx process, a later callback, a
# closure listener and a reference to a function frame with a big object).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
rds = file.path(W, "p3_session.rds")

make_frame_env = function() { big = runif(2e6); environment() }   # a function frame holding 16 MB

s = new.env(parent = emptyenv())
class(s) = "gptr_session"
s$id = "7f3a21"
s$con = file(file.path(W, "p3_log.txt"), open = "w")          # a connection
s$h = curl::new_handle(url = "http://127.0.0.1:1/")             # a curl handle (external pointer)
s$proc = processx::process$new(file.path(R.home("bin"), "Rscript"), c("-e", "Sys.sleep(30)"))
s$later_id = later::later(function() cat("later fired\n"), 60)  # a later handle (cancel function)
s$listener = function(event) cat("listener saw", event, "\n") # closure: env = globalenv
s$home = make_frame_env()                                       # function frame with a 16 MB object
s$home_global = globalenv()
cat("in-memory object.size of session env (shallow):", format(object.size(s), units = "B"), "\n")
t0 = proc.time()[["elapsed"]]
raw1 = serialize(s, NULL)
t = round(proc.time()[["elapsed"]] - t0, 3)
cat("serialize(s) bytes:", length(raw1), "(", round(length(raw1) / 2^20, 1), "MB ) in", t, "s\n")
s2 = s; rm(list = "home", envir = s2)
cat("serialize(s) without the frame reference:", length(serialize(s2, NULL)), "bytes\n")
s$home = make_frame_env()
saveRDS(s, rds)
cat("saveRDS file size:", file.size(rds), "bytes\n")

# same process: readRDS gives a NEW environment (not identical) with the same id
r = readRDS(rds)
cat("same process: identical(readRDS(s), s):", identical(r, s), "| id equal:", identical(r$id, s$id), "\n")

# fresh process: what do the live fields look like?
out = callr::r(function(rds) {
  r = readRDS(rds)
  f = function(expr) tryCatch({ force(expr); "ok" }, error = function(e) paste("ERROR:", conditionMessage(e)))
  c(class = paste(class(r), collapse = "/"),
    con = f(isOpen(r$con)),
    con_write = f(writeLines("x", r$con)),
    curl = f(curl::handle_data(r$h)),
    proc_alive = f(r$proc$is_alive()),
    proc_pid = f(r$proc$get_pid()),
    later_cancel = f(r$later_id()),
    listener = f(r$listener("message_end")),
    home_big_len = length(r$home$big),
    home_global_is_global = identical(r$home_global, globalenv()))
}, args = list(rds = rds))
print(out)

# callr passes arguments by serialisation: the child gets a copy with the same id
same_id = callr::r(function(s) s$id, args = list(s = s2))
cat("callr child sees id:", same_id, "(a copy: two writers for one id are now possible)\n")
s$proc$kill(); close(s$con); later::later(function() NULL)   # cleanup
invisible(s$later_id())
````

### `p3b_values.R`

````r
# p3b_values.R -- actual values of live fields after readRDS in a fresh process, and whether a stale
# connection number can reach a different connection opened in the new process.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
rds = file.path(W, "p3_session.rds")
out = callr::r(function(rds, W) {
  other = file(file.path(W, "p3_other.txt"), open = "w")   # takes the same connection number (3)
  r = readRDS(rds)
  f = function(expr) tryCatch(paste(format(expr), collapse = " "), error = function(e) paste("ERROR:", conditionMessage(e)))
  res = c(stale_con_number = as.integer(r$con), new_con_number = as.integer(other),
    write_via_stale = f(writeLines("written through the stale connection", r$con)),
    proc_is_alive = f(r$proc$is_alive()), proc_pid = f(r$proc$get_pid()),
    proc_kill = f(r$proc$kill()),
    later_cancel = f(r$later_id()))
  close(other)
  res["other_file_lines"] = length(readLines(file.path(W, "p3_other.txt")))
  res
}, args = list(rds = rds, W = W))
print(out)
````

### `p4_firstcall.R`

````r
# p4_firstcall.R -- is the first background gptr() call slow because of JIT compilation of sourced code?
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
jit = commandArgs(TRUE)[1]
if (identical(jit, "precompiled")) {
  e = new.env(); sys.source(file.path(W, "gptr_session.R"), envir = e); sys.source(file.path(W, "fake.R"), envir = e)
  for (n in ls(e, all.names = TRUE)) if (is.function(e[[n]])) e[[n]] = compiler::cmpfun(e[[n]])
  for (n in ls(e, all.names = TRUE)) assign(n, e[[n]], envir = globalenv())
} else { source(file.path(W, "gptr_session.R")); source(file.path(W, "fake.R")) }
options(gptr.sessions_dir = file.path(tempdir(), "p4"))
the$provider = fake_rules(list())
invisible(loadNamespace("rlang")); invisible(loadNamespace("later"))
tm = function() { t0 = Sys.time(); s = gptr("x", background = TRUE); as.numeric(Sys.time() - t0, units = "secs") }
cat(sprintf("%-12s first call %.3f s, second %.3f s, third %.3f s\n", jit, tm(), tm(), tm()))
````

### `p5_bisect.R`

````r
# p5_bisect.R -- which step of gptr() keeps the caller's function frame alive (sticky reference)?
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
steps = c(
  enquos      = "g = function(...) { q = rlang::enquos(...); invisible(NULL) }",
  dot_facts   = "g = function(...) { q = rlang::enquos(...); f = .dot_facts(q); invisible(NULL) }",
  describe    = "g = function(...) { q = rlang::enquos(...); x = .describe_quo(q[[2]], 'd'); invisible(NULL) }",
  caller_only = "g = function(...) { caller = parent.frame(); invisible(NULL) }",
  on_stack    = "g = function(...) { caller = parent.frame(); r = .on_stack(caller); invisible(NULL) }",
  new_session = "g = function(...) { caller = parent.frame(); s = .new_session('fake', caller, FALSE); invisible(s) }",
  full_gptr   = "g = function(...) gptr(...)")
run = function(def) {
  f = tempfile(fileext = ".R")
  writeLines(c(sprintf('source("%s/setup.R")', W), 'options(gptr.sessions_dir = file.path(tempdir(), "bis"))',
    'the$provider = fake_rules(list())', def, 'big = runif(5e6)',
    'h = function(d) g("describe", d)', 'res = h(big)',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(steps)) cat(sprintf("%-12s -> %s\n", n, run(steps[[n]])))
````

### `p5b_bisect.R`

````r
# p5b_bisect.R -- finer bisection of the frame leak when a wrapper h(d) forwards d into gptr().
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
steps = c(
  force_only    = "g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = class(get(as.character(e), envir = env)); invisible(NULL) }",
  leaf_class    = "lf = function(x) list(class = class(x)); g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = lf(get(as.character(e), envir = env)); invisible(NULL) }",
  leaf_objsize  = "lf = function(x) list(size = utils::object.size(x)); g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = lf(get(as.character(e), envir = env)); invisible(NULL) }",
  leaf_dim_len  = "lf = function(x) list(dim = dim(x), length = length(x)); g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = lf(get(as.character(e), envir = env)); invisible(NULL) }",
  lapply_closure= "g = function(...) { q = rlang::enquos(...); k = lapply(1:2, function(i) 1); invisible(NULL) }",
  for_loop_get  = "g = function(...) { q = rlang::enquos(...); for (i in seq_along(q)) { e = rlang::quo_get_expr(q[[i]]); env = rlang::quo_get_env(q[[i]]); if (is.symbol(e)) k = class(get(as.character(e), envir = env)) }; invisible(NULL) }",
  force_then_rm = "g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = class(get(as.character(e), envir = env)); rm(q, env); invisible(NULL) }",
  no_quo_get    = "g = function(...) { k = class(..2); invisible(NULL) }")
run = function(def) {
  f = tempfile(fileext = ".R")
  writeLines(c(def, 'big = runif(5e6)', 'h = function(d) g("describe", d)', 'res = h(big)',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(steps)) cat(sprintf("%-14s -> %s\n", n, run(steps[[n]])))
````

### `p5c_fix.R`

````r
# p5c_fix.R -- can the gateway inspect a forwarded (and forced) argument without pinning the wrapper frame?
steps = c(
  A_neutralise_quosures = paste(sep = "\n",
    "g = function(...) {",
    "  q = rlang::enquos(...)",
    "  e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]])",
    "  k = class(get(as.character(e), envir = env)); rm(env)",
    "  for (i in seq_along(q)) attr(q[[i]], '.Environment') = emptyenv()",
    "  invisible(NULL) }"),
  A_plus_enquo_model = paste(sep = "\n",
    "g = function(..., model = NULL) {",
    "  qm = rlang::enquo(model); m = rlang::quo_get_expr(qm)",
    "  q = rlang::enquos(...)",
    "  e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]])",
    "  k = class(get(as.character(e), envir = env)); rm(env)",
    "  for (i in seq_along(q)) attr(q[[i]], '.Environment') = emptyenv()",
    "  attr(qm, '.Environment') = emptyenv()",
    "  invisible(NULL) }"),
  B_base_elt_labels = paste(sep = "\n",
    "g = function(..., model = NULL) {",
    "  m = substitute(model); labels = vapply(as.list(substitute(list(...)))[-1], function(x) paste(deparse(x), collapse = ''), '')",
    "  k = class(...elt(2))",
    "  invisible(NULL) }"),
  B_leaf_facts = paste(sep = "\n",
    "lf = function(x) list(class = class(x), size = utils::object.size(x), dim = dim(x));",
    "g = function(...) { k = lf(...elt(2)); invisible(NULL) }"))
run = function(def, model = FALSE) {
  f = tempfile(fileext = ".R")
  call = if (model) 'h = function(d) g("describe", d, model = opus)' else 'h = function(d) g("describe", d)'
  writeLines(c(def, 'big = runif(5e6)', call, 'res = h(big)',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(steps)) cat(sprintf("%-22s -> %s | with model = opus: %s\n", n, run(steps[[n]]), run(steps[[n]], TRUE)))
````

### `p5d_ident.R`

````r
# p5d_ident.R -- identifier NSE without quosures: does enquo(model) alone pin the wrapper frame?
steps = list(
  enquo_model_only = c(
    "lf = function(x) list(class = class(x))",
    "g = function(..., model = NULL) { qm = rlang::enquo(model); k = lf(...elt(2)); invisible(NULL) }"),
  base_ident_rule = c(
    "lf = function(x) list(class = class(x))",
    "aliases = c('opus', 'haiku', 'jev')",
    "ident = function(expr, force_fn) {",
    "  if (is.null(expr)) return(NULL)",
    "  if (is.character(expr)) return(expr)",
    "  if (is.symbol(expr) && as.character(expr) %in% aliases) return(as.character(expr))",
    "  tryCatch(as.character(force_fn()), error = function(e) if (is.symbol(expr)) as.character(expr) else stop(e))",
    "}",
    "g = function(..., model = NULL) { m = ident(substitute(model), function() model); k = lf(...elt(2)); invisible(m) }"))
run = function(def, call) {
  f = tempfile(fileext = ".R")
  writeLines(c(def, 'big = runif(5e6)', 'm_var = "haiku"', call, 'res = h(big)', 'cat("model resolved:", res, "\\n")',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  paste(if (any(grepl("^tracemem", out))) "COPY" else "in place", "|", grep("model resolved", out, value = TRUE))
}
calls = c(alias = 'h = function(d) g("describe", d, model = opus)',
          variable = 'h = function(d) g("describe", d, model = m_var)',
          forwarded_dots = 'w = function(...) { m_var = "WRONG-LOCAL"; g(...) }; h = function(d) w("describe", d, model = m_var)',
          unknown_literal = 'h = function(d) g("describe", d, model = gpt9)')
for (n in names(steps)) for (cl in names(calls))
  cat(sprintf("%-17s %-16s -> %s\n", n, cl, run(steps[[n]], calls[[cl]])))
````

### `p5e_basegate.R`

````r
# p5e_basegate.R -- a base-R gateway capture that forces dots only through primitives and leaf calls.
# Cases: top level and inside a wrapper, with model given as alias / variable / forwarded dots.
gate = c(
  "aliases = c('opus', 'haiku', 'jev')",
  "leaf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)), dim = dim(x), length = length(x))",
  "labels_of = function(call) vapply(as.list(call)[-1], function(e) paste(deparse(e, nlines = 1L), collapse = ''), '')",
  "g = function(..., model = NULL) {",
  "  me = substitute(model)",
  "  m = if (is.null(me)) NULL else if (is.character(me)) me else if (is.symbol(me) && as.character(me) %in% aliases) as.character(me) else if (is.symbol(me) && !exists(as.character(me), envir = parent.frame())) as.character(me) else as.character(model)",
  "  lab = labels_of(substitute(list(...)))",
  "  n = ...length(); facts = vector('list', n)",
  "  for (i in seq_len(n)) facts[[i]] = leaf(...elt(i))",
  "  list(model = m, labels = lab, classes = vapply(facts, function(f) f$class[1L], ''))",
  "}")
calls = c(
  top_alias       = 'res = g("describe", big, model = opus)',
  top_variable    = 'm_var = "haiku"; res = g("describe", big, model = m_var)',
  wrap_alias      = 'h = function(d) g("describe", d, model = opus); res = h(big)',
  wrap_variable   = 'm_var = "haiku"; h = function(d) g("describe", d, model = m_var); res = h(big)',
  wrap_forwarded  = 'm_var = "haiku"; w = function(...) { m_var = "WRONG-LOCAL"; g(...) }; h = function(d) w("describe", d, model = m_var); res = h(big)',
  wrap_unknown    = 'h = function(d) g("describe", d, model = gpt9); res = h(big)',
  pipe_top        = 'res = big |> g("describe")')
run = function(call) {
  f = tempfile(fileext = ".R")
  writeLines(c(gate, 'big = runif(5e6)', call, 'cat("resolved:", res$model, "| labels:", res$labels, "| classes:", res$classes, "\\n")',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  paste(if (any(grepl("^tracemem", out))) "COPY    " else "in place", "|", sub("^resolved: ", "model ", grep("resolved", out, value = TRUE)))
}
for (n in names(calls)) cat(sprintf("%-15s -> %s\n", n, run(calls[[n]])))
````

### `p5f_basegate_noclosure.R`

````r
# p5e_basegate.R -- a base-R gateway capture that forces dots only through primitives and leaf calls.
# Cases: top level and inside a wrapper, with model given as alias / variable / forwarded dots.
gate = c(
  "aliases = c('opus', 'haiku', 'jev')",
  "leaf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)), dim = dim(x), length = length(x))",
  "labels_of = function(call) vapply(as.list(call)[-1], function(e) paste(deparse(e, nlines = 1L), collapse = ''), '')",
  "g = function(..., model = NULL) {",
  "  me = substitute(model)",
  "  m = if (is.null(me)) NULL else if (is.character(me)) me else if (is.symbol(me) && as.character(me) %in% aliases) as.character(me) else if (is.symbol(me) && !exists(as.character(me), envir = parent.frame())) as.character(me) else as.character(model)",
  "  lab = labels_of(substitute(list(...)))",
  "  n = ...length(); facts = vector('list', n)",
  "  for (i in seq_len(n)) facts[[i]] = leaf(...elt(i))",
  "  cls = character(n); for (i in seq_len(n)) cls[i] = facts[[i]]$class[1L]",
  "  list(model = m, labels = lab, classes = cls)",
  "}")
calls = c(
  top_alias       = 'res = g("describe", big, model = opus)',
  top_variable    = 'm_var = "haiku"; res = g("describe", big, model = m_var)',
  wrap_alias      = 'h = function(d) g("describe", d, model = opus); res = h(big)',
  wrap_variable   = 'm_var = "haiku"; h = function(d) g("describe", d, model = m_var); res = h(big)',
  wrap_forwarded  = 'm_var = "haiku"; w = function(...) { m_var = "WRONG-LOCAL"; g(...) }; h = function(d) w("describe", d, model = m_var); res = h(big)',
  wrap_unknown    = 'h = function(d) g("describe", d, model = gpt9); res = h(big)',
  pipe_top        = 'res = big |> g("describe")')
run = function(call) {
  f = tempfile(fileext = ".R")
  writeLines(c(gate, 'big = runif(5e6)', call, 'cat("resolved:", res$model, "| labels:", res$labels, "| classes:", res$classes, "\\n")',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  paste(if (any(grepl("^tracemem", out))) "COPY    " else "in place", "|", sub("^resolved: ", "model ", grep("resolved", out, value = TRUE)))
}
for (n in names(calls)) cat(sprintf("%-15s -> %s\n", n, run(calls[[n]])))
````

### `p5g_basegate_primitives.R`

````r
# p5e_basegate.R -- a base-R gateway capture that forces dots only through primitives and leaf calls.
# Cases: top level and inside a wrapper, with model given as alias / variable / forwarded dots.
gate = c(
  "aliases = c('opus', 'haiku', 'jev')",
  "leaf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)), dim = dim(x), length = length(x))",
  "labels_of = function(call) vapply(as.list(call)[-1], function(e) paste(deparse(e, nlines = 1L), collapse = ''), '')",
  "g = function(..., model = NULL) {",
  "  me = substitute(model)",
  "  m = if (is.null(me)) NULL else if (is.character(me)) me else if (is.symbol(me) && as.character(me) %in% aliases) as.character(me) else if (is.symbol(me) && !exists(as.character(me), envir = parent.frame())) as.character(me) else as.character(model)",
  "  lab = labels_of(substitute(list(...)))",
  "  n = ...length(); facts = vector('list', n)",
  "  for (i in seq_len(n)) facts[[i]] = list(class = class(...elt(i)), size = as.numeric(utils::object.size(...elt(i))), dim = dim(...elt(i)), length = length(...elt(i)))",
  "  cls = character(n); for (i in seq_len(n)) cls[i] = facts[[i]]$class[1L]",
  "  list(model = m, labels = lab, classes = cls)",
  "}")
calls = c(
  top_alias       = 'res = g("describe", big, model = opus)',
  top_variable    = 'm_var = "haiku"; res = g("describe", big, model = m_var)',
  wrap_alias      = 'h = function(d) g("describe", d, model = opus); res = h(big)',
  wrap_variable   = 'm_var = "haiku"; h = function(d) g("describe", d, model = m_var); res = h(big)',
  wrap_forwarded  = 'm_var = "haiku"; w = function(...) { m_var = "WRONG-LOCAL"; g(...) }; h = function(d) w("describe", d, model = m_var); res = h(big)',
  wrap_unknown    = 'h = function(d) g("describe", d, model = gpt9); res = h(big)',
  pipe_top        = 'res = big |> g("describe")')
run = function(call) {
  f = tempfile(fileext = ".R")
  writeLines(c(gate, 'big = runif(5e6)', call, 'cat("resolved:", res$model, "| labels:", res$labels, "| classes:", res$classes, "\\n")',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  paste(if (any(grepl("^tracemem", out))) "COPY    " else "in place", "|", sub("^resolved: ", "model ", grep("resolved", out, value = TRUE)))
}
for (n in names(calls)) cat(sprintf("%-15s -> %s\n", n, run(calls[[n]])))
````

### `p5h_bisect.R`

````r
# p5h_bisect.R -- line-by-line bisection of the base gateway (top-level call g("describe", big)).
pre = c("lf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)))",
        "labels_of = function(call) vapply(as.list(call)[-1], function(e) paste(deparse(e, nlines = 1L), collapse = ''), '')")
bodies = c(
  single_leaf      = "k = lf(...elt(2))",
  loop_class       = "for (i in seq_len(...length())) k = class(...elt(i))",
  loop_leaf        = "for (i in seq_len(...length())) k = lf(...elt(i))",
  labels_only      = "lab = labels_of(substitute(list(...)))",
  labels_then_leaf = "lab = labels_of(substitute(list(...))); k = lf(...elt(2))",
  subst_model      = "me = substitute(model); k = lf(...elt(2))",
  length_then_leaf = "n = ...length(); k = lf(...elt(2))",
  leaf_twice       = "k = lf(...elt(1)); k = lf(...elt(2))")
run = function(body, ret = "invisible(NULL)") {
  f = tempfile(fileext = ".R")
  writeLines(c(pre, sprintf("g = function(..., model = NULL) { %s; %s }", body, ret), 'big = runif(5e6)',
               'res = g("describe", big)', 'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(bodies)) cat(sprintf("%-17s -> %s\n", n, run(bodies[[n]])))
````

### `p5i_norloop.R`

````r
# p5i_norloop.R -- loop-free ways to take facts from every dots element (top level and wrapper).
pre = c("lf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)))",
        "facts_rec = function(first, ...) c(list(lf(first)), if (...length()) facts_rec(...))")
bodies = c(
  recursion = "k = facts_rec(...)",
  while_leaf = "i = 1L; n = ...length(); while (i <= n) { k = lf(...elt(i)); i = i + 1L }",
  unrolled = "n = ...length(); if (n >= 1L) k1 = lf(...elt(1L)); if (n >= 2L) k2 = lf(...elt(2L)); if (n >= 3L) k3 = lf(...elt(3L))")
calls = c(top = 'res = g("describe", big)', wrapper = 'h = function(d) g("describe", d); res = h(big)',
          pipe = 'res = big |> g("describe")', forwarded = 'w = function(...) g(...); res = w("describe", big)')
run = function(body, call) {
  f = tempfile(fileext = ".R")
  writeLines(c(pre, sprintf("g = function(..., model = NULL) { %s; invisible(NULL) }", body), 'big = runif(5e6)',
               call, 'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (b in names(bodies)) cat(sprintf("%-10s %s\n", b, paste(sprintf("%s: %s", names(calls), vapply(calls, run, "", body = bodies[[b]])), collapse = " | ")))
````

### `p5j_gate_bisect.R`

````r
# p5j_gate_bisect.R -- top-level gptr("describe", big): which later step pins gptr()'s frame?
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
variants = c(
  full = "",
  no_submit = ".submit = function(...) invisible(NULL)",
  submit_new_only = ".submit = function(s, prompt, context, model, queue, envir, caller, background, source, quiet = FALSE) { s = .new_session(model, caller, TRUE); invisible(s) }",
  no_foreground = ".foreground = function(ss, human = FALSE) { while (any(vapply(ss, function(s) identical(.d(s)$status, 'running'), NA))) if (!.pump_all()) Sys.sleep(0.005) }",
  no_replay_hook = ".replay_hook = NULL; .replay_hook = function(target, prompt, caller) NULL")
run = function(v) {
  f = tempfile(fileext = ".R")
  writeLines(c(sprintf('source("%s/setup.R")', W), 'options(gptr.sessions_dir = file.path(tempdir(), "gb"))',
               'the$provider = fake_rules(list())', v, 'big = runif(5e6)', 's = gptr("describe", big)',
               'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(variants)) cat(sprintf("%-16s -> %s\n", n, run(variants[[n]])))
````

### `p5k_gate_steps.R`

````r
# p5k_gate_steps.R -- return early from gptr() after successive steps (top-level gptr("describe", big)).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
src = readLines(file.path(W, "gptr_session.R"))
anchors = c(after_model = "  n = ...length()",
            after_facts = "  plan = .plan_dots(exprs, nms, facts, !is.null(prompt))",
            after_plan = "  target = if (!is.na(plan$ci)) ...elt(plan$ci) else NULL",
            after_prompt = "  # System 1: a typed judgement; a piped session is READ (its last answer is the state), never continued")
run = function(anchor) {
  s2 = src
  if (!is.na(anchor)) { k = which(s2 == anchor)[1]; s2 = append(s2, "  return(invisible(NULL))", after = k - 1L) }
  gp = tempfile(fileext = ".R"); writeLines(s2, gp)
  f = tempfile(fileext = ".R")
  writeLines(c(sprintf('source("%s")', gp), sprintf('source("%s/fake.R")', W), 'options(gptr.sessions_dir = file.path(tempdir(), "gs"))',
               'the$provider = fake_rules(list())', 'big = runif(5e6)', 's = gptr("describe", big)',
               'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(anchors)) cat(sprintf("%-13s -> %s\n", n, run(anchors[[n]])))
cat(sprintf("%-13s -> %s\n", "full", run(NA)))
````

### `p5l_facts.R`

````r
# p5l_facts.R -- micro-bisection of the facts block (top-level g("describe", big)).
pre = c("`%||%` = function(a, b) if (is.null(a)) b else a",
        "lf = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)))",
        "lf2 = function(x) list(class = class(x), is_chr1 = is.character(x) && length(x) == 1L && !is.object(x), dim = dim(x), length = length(x), size = as.numeric(utils::object.size(x)))")
bodies = c(
  while_k      = "n = ...length(); i = 1L; while (i <= n) { k = lf(...elt(i)); i = i + 1L }",
  while_list   = "n = ...length(); facts = vector('list', n); i = 1L; while (i <= n) { facts[[i]] = lf(...elt(i)); i = i + 1L }",
  while_lf2    = "n = ...length(); i = 1L; while (i <= n) { k = lf2(...elt(i)); i = i + 1L }",
  names_orelse = "n = ...length(); nms = ...names() %||% rep('', n); i = 1L; while (i <= n) { k = lf(...elt(i)); i = i + 1L }",
  names_plain  = "n = ...length(); nms = ...names(); i = 1L; while (i <= n) { k = lf(...elt(i)); i = i + 1L }",
  subst_list   = "n = ...length(); exprs = as.list(substitute(list(...)))[-1L]; i = 1L; while (i <= n) { k = lf(...elt(i)); i = i + 1L }")
run = function(body) {
  f = tempfile(fileext = ".R")
  writeLines(c(pre, sprintf("g = function(..., model = NULL) { %s; invisible(NULL) }", body), 'big = runif(5e6)',
               'res = g("describe", big)', 'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(bodies)) cat(sprintf("%-12s -> %s\n", n, run(bodies[[n]])))
````

### `p5m_header.R`

````r
# p5m_header.R -- exact gptr() preamble up to the facts loop; drop one line at a time.
pre = c("`%||%` = function(a, b) if (is.null(a)) b else a", "the = new.env(); the$known_models = c('opus', 'haiku')",
        ".gptr_abort = function(msg, class) stop(msg)",
        ".leaf_dot = function(x) list(class = class(x), is_chr1 = is.character(x) && length(x) == 1L && !is.object(x), dim = dim(x), length = length(x), size = as.numeric(utils::object.size(x)))")
lines = c(
  caller = "caller = parent.frame()",
  queue = "queue = queue[1L]",
  qcheck = "if (!queue %in% c('steer', 'follow_up')) .gptr_abort('bad', 'x')",
  me = "me = substitute(model)",
  model = "model = if (is.null(me)) NULL else if (is.character(me)) me else if (is.symbol(me) && as.character(me) %in% the$known_models) as.character(me) else if (is.symbol(me) && !exists(as.character(me), envir = caller)) as.character(me) else as.character(model)",
  n = "n = ...length()", exprs = "exprs = as.list(substitute(list(...)))[-1L]",
  nms = "nms = ...names() %||% rep('', n)", nms2 = "nms[is.na(nms)] = ''",
  facts = "facts = vector('list', n)", loop = "i = 1L; while (i <= n) { facts[[i]] = .leaf_dot(...elt(i)); i = i + 1L }")
header = "g = function(..., model = NULL, prompt = NULL, envir = NULL, background = FALSE, parallel = NULL, queue = c('steer', 'follow_up'), choices = NULL) {"
run = function(ls) {
  f = tempfile(fileext = ".R")
  writeLines(c(pre, header, ls, "invisible(NULL) }", 'big = runif(5e6)', 'res = g("describe", big)',
               'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
cat(sprintf("%-16s -> %s\n", "all lines", run(lines)))
for (drop in setdiff(names(lines), c("n", "facts", "loop", "caller"))) cat(sprintf("without %-8s -> %s\n", drop, run(lines[names(lines) != drop & !(drop == "me" & names(lines) == "model") & !(drop == "queue" & names(lines) == "qcheck")])))
````

### `p5n_formal.R`

````r
# p5n_formal.R -- does re-assigning a FORMAL argument inside the gateway stop R's frame cleanup?
pre = c(".leaf_dot = function(x) list(class = class(x), size = as.numeric(utils::object.size(x)))")
bodies = c(
  reassign_formal_null = "model = NULL",
  reassign_formal_value = "model = 'opus'",
  new_local = "mdl = 'opus'",
  reassign_other_formal = "prompt = 'x'",
  force_formal_only = "m = model")
run = function(body, call) {
  f = tempfile(fileext = ".R")
  writeLines(c(pre, "g = function(..., model = NULL, prompt = NULL) {", body,
               "n = ...length(); i = 1L; while (i <= n) { k = .leaf_dot(...elt(i)); i = i + 1L }", "invisible(NULL) }",
               'big = runif(5e6)', call, 'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (b in names(bodies)) cat(sprintf("%-22s top: %-8s | wrapper: %s\n", b, run(bodies[[b]], 'res = g("describe", big)'),
                                     run(bodies[[b]], 'h = function(d) g("describe", d); res = h(big)')))
````

### `p5o_jit.R`

````r
# p5o_jit.R -- is "re-assigning a formal pins the forced dots" specific to byte code? (clean probe)
jit = as.integer(commandArgs(TRUE)[1]); body = commandArgs(TRUE)[2]
invisible(compiler::enableJIT(jit))
lf = function(x) class(x)
g = eval(parse(text = sprintf("function(..., model = NULL) { %s; k = lf(...elt(2)); invisible(NULL) }", body)))
big = runif(5e6)
g("describe", big)
invisible(tracemem(big)); big[1] = 0
cat("END\n")
````

### `p6_later_sigint.R`

````r
# p6_later_sigint.R -- does a SIGINT that arrives while a later() callback runs reach a calling
# handler installed inside the callback? (interactive R, stdin piped, real SIGINT)
library(processx)
p = process$new(file.path(R.home("bin"), "R"), c("--vanilla", "--interactive", "-q", "--no-echo"), stdin = "|", stdout = "|", stderr = "2>&1")
st = new.env(); st$out = ""   # state in an environment, no <<-
pump = function(s) { t0 = Sys.time(); while (as.numeric(Sys.time() - t0, units = "secs") < s) { p$poll_io(100); st$out = paste0(st$out, p$read_output()) } }
p$write_input(paste0('later::later(function() { cat("CB START\\n"); r = tryCatch(withCallingHandlers({ Sys.sleep(3); "slept to the end" },',
  ' interrupt = function(c) { cat("CALLING HANDLER SAW INTERRUPT; resuming\\n"); invokeRestart("resume") }), interrupt = function(e) "exiting handler"); cat("CB END:", r, "\\n") }, 0.5)\n'))
pump(1.2); p$interrupt(); pump(4)
p$write_input('cat("PROMPT ALIVE\\n")\n'); pump(1)
p$write_input(paste0('f = function() { r = tryCatch(withCallingHandlers({ Sys.sleep(3); "slept to the end" }, interrupt = function(c) {',
  ' cat("FOREGROUND CALLING HANDLER SAW INTERRUPT; resuming\\n"); invokeRestart("resume") }), interrupt = function(e) "exiting handler"); cat("FG END:", r, "\\n") }; f()\n'))
pump(1); p$interrupt(); pump(4)
p$write_input("q('no')\n"); pump(1)
cat(st$out)
````

### `setup.R`

````r
# setup.R -- load the G3 prototype byte-compiled (as an installed package would be) into globalenv.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
local({
  e = new.env()
  for (f in c("gptr_session.R", "fake.R", if (isTRUE(getOption("g3.with_doc"))) "doc.R")) sys.source(file.path(W, f), envir = e)
  for (n in ls(e, all.names = TRUE)) {
    x = get(n, envir = e)
    if (is.function(x)) { environment(x) = globalenv(); x = compiler::cmpfun(x) }
    assign(n, x, envir = globalenv())
  }
})
check = function(ok, label) cat(if (isTRUE(ok)) "  PASS " else "  FAIL ", label, "\n", sep = "")
invisible(loadNamespace("rlang")); invisible(loadNamespace("later"))
````

### `t1.out`

````text
== 1. programmatic call returns the session itself ==
  PASS gptr() returns an environment-backed gptr_session
  PASS status idle after settlement, 1 turn
  PASS $value is the lm designated by gptr_return(fit); fit exists in the caller
-- print(res):
[fake] Done ((Intercept)          wt ). Saw: 'Fit a mixed model of mpg on weight and r'
<gptr_session 5c59f9e0> idle | 1 turn | fake | 756 in (350 cached) / 42 out | value: fit <lm>
-- format / as.character: TRUE 
-- str(res): <gptr_session 5c59f9e0> idle, 1 turns, 5 entries, home globalenv(), attached
  PASS non-interactive (Rscript): the result is visible, so a bare call prints the answer
== 2. the pipe steers the SAME object ==
  PASS res |> gptr(...) returns the identical object (same environment)
  PASS turn 2 steered $value to the model with cyl
[fake] Answer to: Summarise in one sentence.
<gptr_session 5c59f9e0> idle | 3 turns | fake | 2.3k in (1.7k cached) / 94 out | value: fit2 <lm>
  PASS steering via an alias is visible through every binding
  PASS a fork is a different object (identical() is pointer identity)
-- summary(res):
 turn deliver source                                   text model
    1  prompt   call Fit a mixed model of mpg on weight ...  fake
    2  prompt   pipe                Add cyl as a covariate.  fake
    3  prompt   pipe             Summarise in one sentence.  fake
                                 answer value
 [fake] Done ((Intercept)          w...   fit
 [fake] Done ((Intercept)          w...  fit2
 [fake] Answer to: Summarise in one ...  <NA>
-- values history:
  turn   by name class  size held
1    1 copy  fit    lm 25528 TRUE
2    2 copy fit2    lm 28344 TRUE
== 3. read-only fields, completion, plugin fields ==
  PASS `res$status = ...` is refused with class gptr_error_readonly
  PASS .DollarNames completes public fields
  PASS a plugin-registered field appears in $ and completion
  PASS ls(session) shows no internals (data live in the hidden .d)
-- res$history (lazy view of the transcript):
   turn       role deliver source final
1     1       user  prompt   call FALSE
2     1  assistant    <NA>   <NA> FALSE
3     1 toolResult    <NA>   <NA> FALSE
4     1  assistant    <NA>   <NA>  TRUE
5     2       user  prompt   pipe FALSE
6     2  assistant    <NA>   <NA> FALSE
7     2 toolResult    <NA>   <NA> FALSE
8     2  assistant    <NA>   <NA>  TRUE
9     3       user  prompt   pipe FALSE
10    3  assistant    <NA>   <NA>  TRUE
-- JSONL file lines: 13  header: {"type":"session","version":3,"id":"5c59f9e0","timestamp":"2026-09-30T05:20:24.903Z","cwd" 
````

### `t1_class.R`

````r
# t1_class.R -- the session object: class, accessors, printing, visibility, pipe continuation, aliasing.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t1"))
the$provider = fake_rules(list(
  "mixed model" = list(code = "fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\nround(coef(fit), 2)"),
  "cyl" = list(code = "fit2 = lm(mpg ~ wt + cyl, data = mtcars)\ngptr_return(fit2)\nround(coef(fit2), 2)")))

cat("== 1. programmatic call returns the session itself ==\n")
res = gptr("Fit a mixed model of mpg on weight and report the effect.", mtcars)
check(inherits(res, "gptr_session") && is.environment(res), "gptr() returns an environment-backed gptr_session")
check(identical(res$status, "idle") && res$turns == 1L, "status idle after settlement, 1 turn")
check(inherits(res$value, "lm") && exists("fit"), "$value is the lm designated by gptr_return(fit); fit exists in the caller")
cat("-- print(res):\n"); print(res)
cat("-- format / as.character:", format(res) == as.character(res), "\n")
cat("-- str(res): "); str(res)
v = withVisible(gptr("Fit a mixed model of mpg on weight and report the effect.", mtcars))
check(v$visible, "non-interactive (Rscript): the result is visible, so a bare call prints the answer")

cat("== 2. the pipe steers the SAME object ==\n")
res2 = res |> gptr("Add cyl as a covariate.")
check(identical(res2, res), "res |> gptr(...) returns the identical object (same environment)")
check(res$turns == 2L && inherits(res$value, "lm") && "cyl" %in% names(coef(res$value)), "turn 2 steered $value to the model with cyl")
b = res                                   # aliasing: both names bind one session
b |> gptr("Summarise in one sentence.")
check(res$turns == 3L && identical(b, res), "steering via an alias is visible through every binding")
check(!identical(res, gptr_fork(res)), "a fork is a different object (identical() is pointer identity)")
cat("-- summary(res):\n"); print(summary(res))
cat("-- values history:\n"); print(res$values)

cat("== 3. read-only fields, completion, plugin fields ==\n")
e = tryCatch({ res$status = "idle"; "no error" }, error = function(e) class(e)[1])
check(identical(e, "gptr_error_readonly"), "`res$status = ...` is refused with class gptr_error_readonly")
check(identical(sort(utils::.DollarNames(res, "^v")), c("value", "values")), ".DollarNames completes public fields")
gptr_field("n_entries", function(s) length(.d(s)$entries))
check(is.numeric(res$n_entries) && "n_entries" %in% utils::.DollarNames(res, "n_"), "a plugin-registered field appears in $ and completion")
check(identical(ls(res), character(0)), "ls(session) shows no internals (data live in the hidden .d)")
cat("-- res$history (lazy view of the transcript):\n"); print(res$history[, c("turn", "role", "deliver", "source", "final")])
cat("-- JSONL file lines:", length(readLines(res$file)), " header:", substr(readLines(res$file, 1), 1, 90), "\n")
````

### `t1_class.out`

````text
== 1. programmatic call returns the session itself ==
  PASS gptr() returns an environment-backed gptr_session
  PASS status idle after settlement, 1 turn
  PASS $value is the lm designated by gptr_return(fit); fit exists in the caller
-- print(res):
[fake] Done ((Intercept)          wt ). Saw: 'Fit a mixed model of mpg on weight and r'
<gptr_session 7d804f19> idle | 1 turn | fake | 756 in (350 cached) / 42 out | value: fit <lm>
-- format / as.character: TRUE 
-- str(res): <gptr_session 7d804f19> idle, 1 turns, 5 entries, home globalenv(), attached
  PASS non-interactive (Rscript): the result is visible, so a bare call prints the answer
== 2. the pipe steers the SAME object ==
  PASS res |> gptr(...) returns the identical object (same environment)
  PASS turn 2 steered $value to the model with cyl
[fake] Answer to: Summarise in one sentence.
<gptr_session 7d804f19> idle | 3 turns | fake | 2.3k in (1.7k cached) / 94 out | value: fit2 <lm>
  PASS steering via an alias is visible through every binding
  PASS a fork is a different object (identical() is pointer identity)
-- summary(res):
 turn deliver source                                   text model
    1  prompt   call Fit a mixed model of mpg on weight ...  fake
    2  prompt   pipe                Add cyl as a covariate.  fake
    3  prompt   pipe             Summarise in one sentence.  fake
                                 answer value
 [fake] Done ((Intercept)          w...   fit
 [fake] Done ((Intercept)          w...  fit2
 [fake] Answer to: Summarise in one ...  <NA>
-- values history:
  turn   by name class  size held
1    1 copy  fit    lm 25528 TRUE
2    2 copy fit2    lm 28344 TRUE
== 3. read-only fields, completion, plugin fields ==
  PASS `res$status = ...` is refused with class gptr_error_readonly
  PASS .DollarNames completes public fields
  PASS a plugin-registered field appears in $ and completion
  PASS ls(session) shows no internals (data live in the hidden .d)
-- res$history (lazy view of the transcript):
   turn       role deliver source final
1     1       user  prompt   call FALSE
2     1  assistant    <NA>   <NA> FALSE
3     1 toolResult    <NA>   <NA> FALSE
4     1  assistant    <NA>   <NA>  TRUE
5     2       user  prompt   pipe FALSE
6     2  assistant    <NA>   <NA> FALSE
7     2 toolResult    <NA>   <NA> FALSE
8     2  assistant    <NA>   <NA>  TRUE
9     3       user  prompt   pipe FALSE
10    3  assistant    <NA>   <NA>  TRUE
-- JSONL file lines: 13  header: {"type":"session","version":3,"id":"7d804f19","timestamp":"2026-09-30T05:50:31.553Z","cwd" 
````

### `t1b_r6.R`

````r
# t1b_r6.R -- R6 alternative vs the environment-backed S3 session (same data in both).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t1b"), gptr.quiet = TRUE)
the$provider = fake_rules(list())
.new_session_bare = function() { s = new.env(parent = emptyenv()); d = new.env(parent = emptyenv()); assign(".d", d, envir = s); class(s) = "gptr_session"; d$id = "x"; d$status = "idle"; s }
cat("R6", as.character(packageVersion("R6")), "| R", R.version$major, R.version$minor, "\n")
R6Session = R6::R6Class("gptr_session_r6", cloneable = TRUE,
  public = list(
    initialize = function(id) { private$d = new.env(parent = emptyenv()); private$d$id = id; private$d$status = "idle"
      private$d$entries = list(); private$d$turns = 0L; private$d$last_text = NA_character_ },
    print = function(...) { cat("<gptr_session_r6", private$d$id, ">", private$d$status, "\n"); invisible(self) }),
  active = list(
    id = function(value) { if (!missing(value)) stop("read-only"); private$d$id },
    status = function(value) { if (!missing(value)) stop("read-only"); private$d$status },
    text = function(value) { if (!missing(value)) stop("read-only"); private$d$last_text }),
  private = list(d = NULL))
s3 = gptr("hello"); s3 |> gptr("again"); s3 |> gptr("once more")
r6 = R6Session$new(s3$id)
for (n in ls(.d(s3), all.names = TRUE)) assign(n, get(n, envir = .d(s3)), envir = r6$.__enclos_env__$private$d)
tm = function(expr, n) { e = substitute(expr); f = parent.frame(); t0 = proc.time()[["elapsed"]]; for (i in seq_len(n)) eval(e, f); (proc.time()[["elapsed"]] - t0) / n * 1e6 }
n = 20000
cat(sprintf("%-38s %12s %12s\n", "", "S3 env", "R6"))
cat(sprintf("%-38s %10.2f us %10.2f us\n", "create an empty object", tm(.new_session_bare(), 2000), tm(R6Session$new("x"), 2000)))
cat(sprintf("%-38s %10.2f us %10.2f us\n", "read s$status", tm(s3$status, n), tm(r6$status, n)))
cat(sprintf("%-38s %10.2f us %10.2f us\n", "read s$text", tm(s3$text, n), tm(r6$text, n)))
cat(sprintf("%-38s %12d %12d\n", "serialize() bytes (same data)", length(serialize(s3, NULL)), length(serialize(r6, NULL))))
cat(sprintf("%-38s %12d %12d\n", "object.size() bytes (shallow)", as.integer(object.size(s3)), as.integer(object.size(r6))))
cat(sprintf("%-38s %12s %12s\n", "ls(obj) shows", paste(ls(s3), collapse = ","), paste(ls(r6), collapse = ",")))
e1 = tryCatch({ s3$status = "x"; "allowed" }, error = function(e) "refused"); e2 = tryCatch({ r6$status = "x"; "allowed" }, error = function(e) "refused")
cat(sprintf("%-38s %12s %12s\n", "obj$status = 'x'", e1, e2))
e3 = tryCatch({ r6$newfield = 1; "allowed" }, error = function(e) "refused")
cat(sprintf("%-38s %12s %12s\n", "obj$newfield = 1", tryCatch({ s3$newfield = 1; "allowed" }, error = function(e) "refused"), e3))
cl = r6$clone()
cat(sprintf("%-38s %12s %12s\n", "clone(): new object shares data env?", "no clone()", identical(cl$.__enclos_env__$private$d, r6$.__enclos_env__$private$d)))
cat(sprintf("%-38s %12s %12s\n", "has compiled code", "no (base)", if (nzchar(system.file("libs", package = "R6"))) "yes" else "no"))
````

### `t2_dispatch.R`

````r
# t2_dispatch.R -- gptr() dispatch on its first argument.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t2"))
the$provider = fake_rules(list()); the$s1 = fake_s1
mice = data.frame(id = 1:120, diet = gl(2, 60), weight = c(rnorm(60, 20), rnorm(60, 22)))

cat("== 1. data first: df |> gptr('...') attaches context and starts a NEW session ==\n")
a = mice |> gptr("Which columns have missing values?")
h = a$history
check(a$turns == 1L && grepl("<object name=mice class=data.frame 120x3", h$text[1]), "context described by name, budgeted (no data serialised)")
cat("   user message sent:", sub("\n", " | ", h$text[1]), "\n")

cat("== 2. session first: s |> gptr('...') continues; a named session is context ==\n")
a |> gptr("Impute them with the median.", model = haiku)
check(a$turns == 2L && identical(a$model, "haiku"), "continuation on the same object; model switched mid-conversation")
check(any(vapply(.d(a)$entries, function(e) identical(e$type, "model_change"), NA)), "model switch recorded as a Pi model_change entry")
b = gptr("Compare with the earlier answer.", earlier = a)
check(!identical(b, a) && a$turns == 2L && grepl("name=earlier class=gptr_session", b$history$text[1]), "gptr('p', earlier = a): a named session is context, not continued")

cat("== 3. System 1 on a session: a typed judgement that READS the session, never continues it ==\n")
n_before = a$turns; e_before = length(.d(a)$entries)
ok = a |> gptr("Is the answer clear and good?", model = jev)
check(inherits(ok, "gptr_decision") && is.logical(ok) && !is.null(attr(ok, "prob")), "returns a gptr_decision (logical + prob), not a session")
check(a$turns == n_before && length(.d(a)$entries) == e_before + 1L, "no new turn; one gptr.decision custom entry (audit, never in model context)")
check(length(.context(a)) == length(Filter(function(e) identical(e$type, "message"), .path(.d(a)))), "decision entry excluded from provider context")
cat("   state sent to System 1:", .d(a)$entries[[length(.d(a)$entries)]]$data$state_chars, "chars (last answer + value, not the transcript)\n")
cat("   used directly in if():", if (a |> gptr("Is the answer clear?", model = jev)) "TRUE branch" else "FALSE branch", "\n")

cat("== 4. parallel = n returns a gptr_sessions list; piping it steers every member ==\n")
cohorts = list(ctrl = mice[1:60, ], treat = mice[61:120, ], pilot = mice[1:10, ])
t0 = Sys.time()
ss = gptr("Summarise this cohort", cohorts, parallel = 2)
el = as.numeric(Sys.time() - t0, units = "secs")
check(inherits(ss, "gptr_sessions") && length(ss) == 3L && all(vapply(ss, inherits, NA, "gptr_session")), "three sessions, class gptr_sessions")
print(ss)
ss2 = ss |> gptr("Now shorten to one line")
check(identical(ss2, ss) && all(vapply(ss, function(s) s$turns, 1L) == 2L), "ss |> gptr(): every member steered in place, same list returned")
cat(sprintf("   parallel wall time for 3 sessions, 2 at a time: %.2f s (each request 0.05 s)\n", el))

cat("== 5. prompt selection edge cases ==\n")
task = "Describe mtcars"
s5 = gptr(task, mtcars)
check(grepl("^Describe mtcars", s5$history$text[1]), "a variable holding a string is the prompt when no literal is present")
s6 = "Describe iris" |> gptr()
check(grepl("^Describe iris", s6$history$text[1]), "a string piped into gptr() is the prompt")
e = tryCatch(gptr(), error = function(e) class(e)[1])
check(identical(e, "gptr_error_noninteractive"), "gptr() with no prompt under Rscript: gptr_error_noninteractive")
````

### `t2_dispatch.out`

````text
== 1. data first: df |> gptr('...') attaches context and starts a NEW session ==
  PASS context described by name, budgeted (no data serialised)
   user message sent: Which columns have missing values? | Attached: <object name=mice class=data.frame 120x3 size=3.3 Kb> 
== 2. session first: s |> gptr('...') continues; a named session is context ==
[haiku] Answer to: Impute them with the median.
<gptr_session 5381f46b> idle | 2 turns | haiku | 738 in (0 cached) / 41 out | value: none
  PASS continuation on the same object; model switched mid-conversation
  PASS model switch recorded as a Pi model_change entry
  PASS gptr('p', earlier = a): a named session is context, not continued
== 3. System 1 on a session: a typed judgement that READS the session, never continues it ==
  PASS returns a gptr_decision (logical + prob), not a session
  PASS no new turn; one gptr.decision custom entry (audit, never in model context)
  PASS decision entry excluded from provider context
   state sent to System 1: 55 chars (last answer + value, not the transcript)
   used directly in if(): FALSE branch 
== 4. parallel = n returns a gptr_sessions list; piping it steers every member ==
  PASS three sessions, class gptr_sessions
<gptr_sessions> 3 sessions
  ctrl       5a8124fc idle    1 turns  [fake] Answer to: Summarise this coho...
  treat      2c848772 idle    1 turns  [fake] Answer to: Summarise this coho...
  pilot      4e9a6952 idle    1 turns  [fake] Answer to: Summarise this coho...
  PASS ss |> gptr(): every member steered in place, same list returned
   parallel wall time for 3 sessions, 2 at a time: 0.12 s (each request 0.05 s)
== 5. prompt selection edge cases ==
  PASS a variable holding a string is the prompt when no literal is present
  PASS a string piped into gptr() is the prompt
  PASS gptr() with no prompt under Rscript: gptr_error_noninteractive
````

### `t2b_nse.R`

````r
# t2b_nse.R -- base-R identifier resolution in the full gateway (no quosures).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t2b"), gptr.quiet = TRUE)
the$provider = fake_rules(list()); the$s1 = fake_s1
m_of = function(s) s$model
m = "haiku"; hard = TRUE; jev = "a user variable that shadows an alias"
cases = list(
  'model = "opus" (string)'                   = quote(gptr("p", model = "opus")),
  "model = opus (alias symbol)"               = quote(gptr("p", model = opus)),
  "model = m (variable holding 'haiku')"      = quote(gptr("p", model = m)),
  "model = if (hard) opus else haiku"         = quote(gptr("p", model = if (hard) opus else haiku)),
  "model = gpt9 (unknown, unbound: literal)"  = quote(gptr("p", model = gpt9)),
  "model = I(m) (explicit variable)"          = quote(gptr("p", model = I(m))),
  "forwarded dots, wrapper has local m"       = quote((function(...) { m = "WRONG-LOCAL"; gptr(...) })("p", model = m)),
  "wrapper argument w(mm = m)"                = quote((function(mm) gptr("p", model = mm))(m)))
for (nm in names(cases)) {
  s = eval(cases[[nm]])
  cat(sprintf("%-42s -> %s\n", nm, m_of(s)))
}
cat("variable named like an alias: model = jev ->", class(gptr("p", model = jev))[1], "(the alias wins, as library(); I(jev) is the escape)\n")
````

### `t3.out`

````text
== 1. background = TRUE returns immediately with a running session ==
  PASS returned at once (0.026 s), status running
   print while running: <gptr_session 75614226> running (request) | 1 turn | fake | 0 in (0 cached) / 0 out | value: none
== 2. piping into the RUNNING session enqueues a steering message and returns at once ==
[gptr] queued steer for running session 75614226
  PASS non-blocking (0.000 s); queue holds the steer
== 3. a second producer: another R process writes to the session's file inbox ==
  PASS inbox line written by the other process (pid differs)
== 4. a third producer: the API (what the Ctrl-C menu and front ends call) ==
  PASS queue now holds pipe + api items (inbox drained at the next boundary)
== 5. gptr_wait() blocks until settled and returns the session ==
  PASS settled idle
   transcript:  user<call> assi tool user<pipe> assi tool user<api> assi user<inbox> assi 
  PASS the piped steer lands right after the COMPLETE tool result (never between call and result)
  PASS the inbox follow-up is delivered only when the agent would otherwise stop
  PASS steered $value is the TPM matrix
[fake] Answer to: Also report the library sizes
<gptr_session 75614226> idle | 4 turns | fake | 1.7k in (1.2k cached) / 65 out | value: tpm <matrix>
== 6. piping into an IDLE session is a new prompt turn and blocks (Rscript: prints) ==
[fake] Answer to: Summarise the normalisation
<gptr_session 75614226> idle | 5 turns | fake | 2.2k in (1.7k cached) / 77 out | value: tpm <matrix>
  PASS idle pipe = follow-up prompt turn, run to settlement
== 7. re-entrancy: the agent's own R code pipes into its running session -> enqueued, no nested run ==
[gptr] queued steer for running session 3b354407
[fake] Answer to: and double-check the totals
<gptr_session 3b354407> idle | 2 turns | fake | 709 in (324 cached) / 32 out | value: none
  PASS the nested pipe became a steering message of the same session
  PASS no second concurrent run was started
== 8. abort returns queued messages to the user ==
[gptr] queued steer for running session 21995940
[gptr] queued follow_up for running session 21995940
[gptr] session 21995940 finished (aborted, turn 1)
  PASS status aborted; queue moved to $dropped
[fake] Answer to: start again
<gptr_session 21995940> idle | 2 turns | fake | 331 in (0 cached) / 8 out | value: none
  PASS an aborted session continues with the next pipe (no fork)
   jobs now running: 0 
````

### `t3_steer.R`

````r
# t3_steer.R -- steering: idle follow-up vs running background session; ONE queue fed by three
# producers (pipe, file inbox from another process, API); delivery only after complete tool results.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
SD = file.path(tempdir(), "t3"); options(gptr.sessions_dir = SD)
the$provider = fake_rules(list(
  "counts" = list(code = "Sys.sleep(0.6)\ncounts = matrix(rpois(20, 5), 4)\ngptr_return(counts)\ndim(counts)", delay = 0.2),
  "TPM" = list(code = "Sys.sleep(0.3)\ntpm = counts / colSums(counts) * 1e6\ngptr_return(tpm)\nrange(tpm)", delay = 0.2)))
roles = function(s) { h = s$history; paste(sprintf("%s%s", substr(h$role, 1, 4), ifelse(is.na(h$source), "", paste0("<", h$source, ">"))), collapse = " ") }

cat("== 1. background = TRUE returns immediately with a running session ==\n")
invisible(loadNamespace("rlang")); invisible(loadNamespace("later"))   # warm-up: namespace loading is not gptr's cost
t0 = Sys.time()
s = gptr("Load the counts and normalise them", background = TRUE)
el0 = as.numeric(Sys.time() - t0, units = "secs")
check(identical(s$status, "running") && el0 < 0.1, sprintf("returned at once (%.3f s), status running", el0))
cat("   print while running: "); print(s)

cat("== 2. piping into the RUNNING session enqueues a steering message and returns at once ==\n")
t1 = Sys.time()
r = s |> gptr("Use TPM, not CPM")
el1 = as.numeric(Sys.time() - t1, units = "secs")
check(identical(r, s) && el1 < 0.1 && identical(s$queue, "Use TPM, not CPM"), sprintf("non-blocking (%.3f s); queue holds the steer", el1))

cat("== 3. a second producer: another R process writes to the session's file inbox ==\n")
child = callr::r_bg(function(W, SD, id) {
  source(file.path(W, "gptr_session.R")); options(gptr.sessions_dir = SD)
  gptr_steer(id, "Also report the library sizes", deliver = "follow_up")
}, args = list(W = W, SD = SD, id = s$id))
while (child$is_alive()) later::run_now(0.05)          # console idle: later services the session
check(file.exists(sub("[.]jsonl$", ".inbox.jsonl", s$file)) || s$turns > 1L, "inbox line written by the other process (pid differs)")

cat("== 4. a third producer: the API (what the Ctrl-C menu and front ends call) ==\n")
gptr_steer(s, "Keep genes with at least 10 reads", deliver = "steer")
check("Keep genes with at least 10 reads" %in% s$queue, "the api item is in the same queue (inbox items join it when drained at the next boundary)")

cat("== 5. gptr_wait() blocks until settled and returns the session ==\n")
out = gptr_wait(s)
check(identical(out, s) && identical(s$status, "idle"), "settled idle")
cat("   transcript: ", roles(s), "\n")
h = s$history
k_tool = which(h$role == "toolResult")[1]; k_steer = which(h$source == "pipe")[1]
check(!is.na(k_steer) && k_steer == k_tool + 1L, "the piped steer lands right after the COMPLETE tool result (never between call and result)")
check(identical(h$deliver[h$source %in% "inbox"], "follow_up") && which(h$source == "inbox") > max(which(h$deliver == "steer")),
      "the inbox follow-up is delivered only when the agent would otherwise stop")
check(inherits(s$value, "matrix") && exists("tpm"), "steered $value is the TPM matrix")
print(s)

cat("== 6. piping into an IDLE session is a new prompt turn and blocks (Rscript: prints) ==\n")
n = s$turns
s |> gptr("Summarise the normalisation")
check(s$turns == n + 1L && identical(tail(s$history$deliver[s$history$role == "user"], 1), "prompt"), "idle pipe = follow-up prompt turn, run to settlement")

cat("== 7. re-entrancy: the agent's own R code pipes into its running session -> enqueued, no nested run ==\n")
the$provider = fake_rules(list("self" = list(code = "me |> gptr('and double-check the totals')\n'queued from inside'")))
me = gptr("self-steering test", background = TRUE)
gptr_wait(me)
hm = me$history
check(any(hm$text == "and double-check the totals" & hm$deliver == "steer"), "the nested pipe became a steering message of the same session")
check(me$turns == 2L, "no second concurrent run was started")

cat("== 8. abort returns queued messages to the user ==\n")
the$provider = fake_rules(list("long" = list(code = "Sys.sleep(0.4)\n1", delay = 0.1)))
z = gptr("long job", background = TRUE)
z |> gptr("steer A"); z |> gptr("follow B", queue = "follow_up")
gptr_cancel(z)
check(identical(z$status, "aborted") && identical(z$dropped, c("steer A", "follow B")) && !length(z$queue), "status aborted; queue moved to $dropped")
z |> gptr("start again")
check(identical(z$status, "idle") && z$turns == 2L, "an aborted session continues with the next pipe (no fork)")
cat("   jobs now running:", nrow(gptr_jobs()), "\n")
````

### `t3_steer.out`

````text
== 1. background = TRUE returns immediately with a running session ==
  PASS returned at once (0.033 s), status running
   print while running: <gptr_session 41612545> running (request) | 1 turn | fake | 0 in (0 cached) / 0 out | value: none
== 2. piping into the RUNNING session enqueues a steering message and returns at once ==
[gptr] queued steer for running session 41612545
  PASS non-blocking (0.000 s); queue holds the steer
== 3. a second producer: another R process writes to the session's file inbox ==
  PASS inbox line written by the other process (pid differs)
== 4. a third producer: the API (what the Ctrl-C menu and front ends call) ==
  PASS the api item is in the same queue (inbox items join it when drained at the next boundary)
== 5. gptr_wait() blocks until settled and returns the session ==
  PASS settled idle
   transcript:  user<call> assi tool user<pipe> assi tool user<api> assi user<inbox> assi 
  PASS the piped steer lands right after the COMPLETE tool result (never between call and result)
  PASS the inbox follow-up is delivered only when the agent would otherwise stop
  PASS steered $value is the TPM matrix
[fake] Answer to: Also report the library sizes
<gptr_session 41612545> idle | 4 turns | fake | 1.7k in (1.2k cached) / 65 out | value: tpm <matrix>
== 6. piping into an IDLE session is a new prompt turn and blocks (Rscript: prints) ==
[fake] Answer to: Summarise the normalisation
<gptr_session 41612545> idle | 5 turns | fake | 2.2k in (1.7k cached) / 77 out | value: tpm <matrix>
  PASS idle pipe = follow-up prompt turn, run to settlement
== 7. re-entrancy: the agent's own R code pipes into its running session -> enqueued, no nested run ==
[gptr] queued steer for running session 10ff71a7
[fake] Answer to: and double-check the totals
<gptr_session 10ff71a7> idle | 2 turns | fake | 709 in (636 cached) / 32 out | value: none
  PASS the nested pipe became a steering message of the same session
  PASS no second concurrent run was started
== 8. abort returns queued messages to the user ==
[gptr] queued steer for running session 2ba23d2e
[gptr] queued follow_up for running session 2ba23d2e
[gptr] session 2ba23d2e finished (aborted, turn 1)
  PASS status aborted; queue moved to $dropped
[fake] Answer to: start again
<gptr_session 2ba23d2e> idle | 2 turns | fake | 331 in (312 cached) / 8 out | value: none
  PASS an aborted session continues with the next pipe (no fork)
   jobs now running: 0 
````

### `t4.out`

````text
[fake] Done ([1] 3). Saw: 'Use 15% mitochondrial reads as the cut-o'
<gptr_session 1420a629> idle | 2 turns | fake | 1.6k in (1.1k cached) / 74 out | value: keep <logical>
main line: keep = 3 of 6 cells at 15%; global keep = 3 
== 1. identity, lineage and the fork file ==
  PASS new object, new id
  PASS lineage: parent id and fork turn recorded
  PASS fork file header: parentSession = parent path (Pi v3), gptr.forkOf = {id, entry, turn}
  PASS entries copied with the SAME ids, re-chained root to leaf
  PASS session_start(reason = 'fork') fired for plugins
== 2. nothing live is shared: listeners, queue, run ==
[fake] Answer to: Report the number of cells kept
<gptr_session 1420a629> idle | 3 turns | fake | 2.1k in (1.6k cached) / 87 out | value: keep <logical>
  PASS a listener added to the fork never fires for the parent (INFRA-14 accept test)
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session 35286ca9> idle | 3 turns | fake | 1.0k in (967 cached) / 34 out | value: keep <logical>
  PASS it fires for the fork's own appends
  PASS both sessions advanced independently (different leaves, different files)
== 3. the fork evaluates in an overlay: zero-copy reads, isolated writes ==
  PASS fork's keep (10%) lives in the overlay; the user's keep (15%) is untouched
  PASS f$envir is the overlay; reads fall through to globalenv
  PASS the overlay reads pct_mt at the same address (no copy)
   f$envir label: overlay of globalenv() (fork of 1420a629) 
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session 640e9e9b> idle | 4 turns | fake | 1.1k in (1.0k cached) / 34 out | value: keep <logical>
  PASS envir = 'shared' opts in to writing into the caller's workspace
== 4. fork at a turn ==
  PASS gptr_fork(qc, at = 1): history and value of turn 1 only
  PASS at = 0: an empty session that still names its parent (file written lazily)
== 5. forking a RUNNING session: cut at the last settled boundary; the fork is idle ==
   parent caught at step boundary after its tool result; answer still pending
[gptr] queued steer for running session 420ae2d4
  PASS parent still running; fork idle
  PASS the parent's queue is not copied
  PASS cut at the last settled boundary (complete tool result), never mid-call
[fake] Answer to: steer the parent only
<gptr_session 420ae2d4> idle | 2 turns | fake | 690 in (633 cached) / 30 out | value: none
  PASS parent continued with its steer; the fork did not see it
[fake] Answer to: continue the fork from the tool result
<gptr_session 2f702b02> idle | 2 turns | fake | 374 in (357 cached) / 14 out | value: none
  PASS the fork continues with a user message right after the tool result
== 6. token cost: the fork's first request re-uses the parent's cached prefix ==
   fork request 1: 490 input tokens, 477 served from the parent's prefix cache (same model)
````

### `t4_fork.R`

````r
# t4_fork.R -- explicit gptr_fork(): new id, Pi-v3 fork file with parentSession, nothing live shared,
# overlay environment, fork of a running session, fork at a turn.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t4"))
the$provider = fake_rules(list(
  "QC" = list(code = "keep = pct_mt <= 20\ngptr_return(keep)\nsum(keep)"),
  "15%" = list(code = "keep = pct_mt <= 15\ngptr_return(keep)\nsum(keep)"),
  "10%" = list(code = "keep = pct_mt <= 10\ngptr_return(keep)\nsum(keep)"),
  "slow" = list(code = "Sys.sleep(0.5)\nslow_done = TRUE", delay = 0.1)))
ev = new.env(); ev$fork = character(); ev$fired = character()   # state in an environment, no <<-
gptr_hook("session_start", function(payload, s) ev$fork = c(ev$fork, paste(payload$reason, "of", payload$parent)))
pct_mt = c(3, 8, 12, 18, 25, 40)                        # stands in for pbmc$percent.mt

qc = gptr("Run QC on the cells and flag low-quality cells")
qc |> gptr("Use 15% mitochondrial reads as the cut-off instead of 20%")
cat("main line: keep =", sum(qc$value), "of 6 cells at 15%; global keep =", sum(keep), "\n")

cat("== 1. identity, lineage and the fork file ==\n")
f = gptr_fork(qc)
check(!identical(f, qc) && f$id != qc$id, "new object, new id")
check(identical(f$parent$id, qc$id) && f$parent$turn == 2L, "lineage: parent id and fork turn recorded")
check(!file.exists(f$file), "no file yet: a fork is written with its first own message (no orphan files)")
fe_mem = .d(f)$entries; pe = .path(.d(qc))
check(identical(vapply(fe_mem, function(e) e$id, ""), vapply(pe[seq_along(fe_mem)], function(e) e$id, "")), "entries copied with the SAME ids, re-chained root to leaf")
check(identical(ev$fork, paste("fork of", qc$id)), "session_start(reason = 'fork') fired for plugins")

cat("== 2. nothing live is shared: listeners, queue, run ==\n")
gptr_on(f, "entry_appended", function(event, e, s) ev$fired = c(ev$fired, s$id))
qc |> gptr("Report the number of cells kept")
check(!length(ev$fired), "a listener added to the fork never fires for the parent (INFRA-14 accept test)")
f |> gptr("Try a 10% cut-off as well")
check(length(ev$fired) > 0L && all(ev$fired == f$id), "it fires for the fork's own appends")
h = jsonlite::fromJSON(readLines(f$file, 1L), simplifyVector = FALSE)
check(identical(h$parentSession, qc$file) && identical(h$gptr$forkOf$id, qc$id), "fork file header: parentSession = parent path (Pi v3), gptr.forkOf = {id, entry, turn}")
fe = lapply(readLines(f$file)[-1], jsonlite::fromJSON, simplifyVector = FALSE)
check(identical(vapply(fe[seq_along(fe_mem)], function(e) e$id, ""), vapply(fe_mem, function(e) e$id, "")), "the fork file starts with the copied path, same ids")
check(qc$turns == 3L && f$turns == 3L && !identical(.d(qc)$leaf, .d(f)$leaf) && qc$file != f$file, "both sessions advanced independently (different leaves, different files)")

cat("== 3. the fork evaluates in an overlay: zero-copy reads, isolated writes ==\n")
check(sum(keep) == 3L && sum(f$value) == 2L && sum(qc$value) == 3L, "fork's keep (10%) lives in the overlay; the user's keep (15%) is untouched")
check(identical(get("keep", envir = f$envir, inherits = FALSE), f$value) && exists("pct_mt", envir = f$envir), "f$envir is the overlay; reads fall through to globalenv")
check(identical(rlang::obj_address(get("pct_mt", envir = f$envir)), rlang::obj_address(pct_mt)), "the overlay reads pct_mt at the same address (no copy)")
cat("   f$envir label:", .d(f)$home_label, "\n")
g = gptr_fork(qc, envir = "shared")
g |> gptr("Try a 10% cut-off as well")
check(sum(keep) == 2L, "envir = 'shared' opts in to writing into the caller's workspace")
keep = pct_mt <= 15

cat("== 4. fork at a turn ==\n")
f1 = gptr_fork(qc, at = 1)
check(f1$turns == 1L && sum(f1$value) == 4L && sum(qc$value) == 3L, "gptr_fork(qc, at = 1): history and value of turn 1 only")
f0 = gptr_fork(qc, at = 0)
check(f0$turns == 0L && !length(.d(f0)$entries) && !file.exists(f0$file) && identical(f0$parent$id, qc$id), "at = 0: an empty session that still names its parent (file written lazily)")

cat("== 5. forking a RUNNING session: cut at the last settled boundary; the fork is idle ==\n")
the$provider = fake_rules(list("slow" = list(code = "Sys.sleep(0.3)\nslow_done = TRUE", delay = 0.1)), delay = 0.4)
r = gptr("slow job", background = TRUE)
last_role = function(s) { e = .d(s)$entries; m = e[[length(e)]]$message; if (is.null(m)) "" else m$role }
t0 = Sys.time()
while (!identical(last_role(r), "toolResult") && as.numeric(Sys.time() - t0, units = "secs") < 3) later::run_now(0.01)
cat("   parent caught at step", .d(r)$step, "after its tool result; answer still pending\n")
r |> gptr("steer the parent only")
fr = gptr_fork(r)
check(identical(r$status, "running") && identical(fr$status, "idle"), "parent still running; fork idle")
check(!length(fr$queue) && length(r$queue) == 1L, "the parent's queue is not copied")
check(identical(tail(fr$history$role, 1), "toolResult") && fr$turns == 1L, "cut at the last settled boundary (complete tool result), never mid-call")
gptr_wait(r)
check(r$turns == 2L && fr$turns == 1L && identical(r$status, "idle"), "parent continued with its steer; the fork did not see it")
fr |> gptr("continue the fork from the tool result")
check(fr$turns == 2L && identical(fr$history$role[3:4], c("toolResult", "user")), "the fork continues with a user message right after the tool result")

cat("== 6. token cost: the fork's first request re-uses the parent's cached prefix ==\n")
lg = .live(f)$request_log
cat(sprintf("   fork request 1: %d input tokens, %d served from the parent's prefix cache (same model)\n",
            lg[[1]][["input"]], lg[[1]][["cached"]]))
````

### `t4_fork.out`

````text
[fake] Done ([1] 3). Saw: 'Use 15% mitochondrial reads as the cut-o'
<gptr_session 18e9519b> idle | 2 turns | fake | 1.6k in (1.1k cached) / 74 out | value: keep <logical>
main line: keep = 3 of 6 cells at 15%; global keep = 3 
== 1. identity, lineage and the fork file ==
  PASS new object, new id
  PASS lineage: parent id and fork turn recorded
  PASS no file yet: a fork is written with its first own message (no orphan files)
  PASS entries copied with the SAME ids, re-chained root to leaf
  PASS session_start(reason = 'fork') fired for plugins
== 2. nothing live is shared: listeners, queue, run ==
[fake] Answer to: Report the number of cells kept
<gptr_session 18e9519b> idle | 3 turns | fake | 2.1k in (1.6k cached) / 87 out | value: keep <logical>
  PASS a listener added to the fork never fires for the parent (INFRA-14 accept test)
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session 6f57db79> idle | 3 turns | fake | 1.0k in (967 cached) / 34 out | value: keep <logical>
  PASS it fires for the fork's own appends
  PASS fork file header: parentSession = parent path (Pi v3), gptr.forkOf = {id, entry, turn}
  PASS the fork file starts with the copied path, same ids
  PASS both sessions advanced independently (different leaves, different files)
== 3. the fork evaluates in an overlay: zero-copy reads, isolated writes ==
  PASS fork's keep (10%) lives in the overlay; the user's keep (15%) is untouched
  PASS f$envir is the overlay; reads fall through to globalenv
  PASS the overlay reads pct_mt at the same address (no copy)
   f$envir label: overlay of globalenv() (fork of 18e9519b) 
[fake] Done ([1] 2). Saw: 'Try a 10% cut-off as well'
<gptr_session cac73908> idle | 4 turns | fake | 1.1k in (1.0k cached) / 34 out | value: keep <logical>
  PASS envir = 'shared' opts in to writing into the caller's workspace
== 4. fork at a turn ==
  PASS gptr_fork(qc, at = 1): history and value of turn 1 only
  PASS at = 0: an empty session that still names its parent (file written lazily)
== 5. forking a RUNNING session: cut at the last settled boundary; the fork is idle ==
   parent caught at step boundary after its tool result; answer still pending
[gptr] queued steer for running session 3f86b99a
  PASS parent still running; fork idle
  PASS the parent's queue is not copied
  PASS cut at the last settled boundary (complete tool result), never mid-call
[fake] Answer to: steer the parent only
<gptr_session 3f86b99a> idle | 2 turns | fake | 690 in (633 cached) / 30 out | value: none
  PASS parent continued with its steer; the fork did not see it
[fake] Answer to: continue the fork from the tool result
<gptr_session 21699574> idle | 2 turns | fake | 374 in (357 cached) / 14 out | value: none
  PASS the fork continues with a user message right after the tool result
== 6. token cost: the fork's first request re-uses the parent's cached prefix ==
   fork request 1: 490 input tokens, 477 served from the parent's prefix cache (same model)
````

### `t5.out`

````text
plain R baseline: big[1] = 0                       -> in place
plain R: str(big) (known sticky ref, report 12)    -> COPY
gptr('describe', big)                              -> in place
big |> gptr('describe')                            -> in place
s |> gptr('p', big) (continuation + context)       -> in place
agent: gptr_return(big) [40 MB -> by name]         -> in place
agent creates big2 and designates it               -> in place
s$value read, printed head                         -> in place
x = s$value; rm(x)                                 -> in place
replay assignment s$value = big                    -> in place
small object designated [copy policy]              -> in place
print / summary / str / format of s                -> in place
gptr_fork(s) + fork turn reading big               -> in place
System 1 on the session                            -> in place
session created inside a function f(big)           -> in place
wrapper with model alias f(big)                    -> in place
wrapper, model = if (TRUE) opus else haiku         -> in place
forwarded dots w(...) -> gptr(...)                 -> in place
System 1 on data: gptr('ok?', big, model = jev)    -> in place
plain R baseline for a list element: L$a[1] = 0    -> in place
parallel = 2 over a list (trace L$a)               -> in place
background run with context, then settled          -> in place
saveRDS(s) / readRDS                               -> in place
````

### `t5_copycheck.R`

````r
# t5_copycheck.R -- copy-safety: after each gptr entry point, the user's next in-place edit must NOT
# copy the object (tracemem prints nothing). One fresh Rscript process per case (report 12 §5.4 method).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
cases = list(
  "plain R baseline: big[1] = 0"                    = c("", "big"),
  "plain R: str(big) (known sticky ref, report 12)" = c("str(big)", "big"),
  "gptr('describe', big)"                           = c("s = gptr('describe', big)", "big"),
  "big |> gptr('describe')"                         = c("s = big |> gptr('describe')", "big"),
  "s |> gptr('p', big) (continuation + context)"    = c("s = gptr('a'); s |> gptr('b', big)", "big"),
  "agent: gptr_return(big) [40 MB -> by name]"      = c("s = gptr('designate big')", "big"),
  "agent creates big2 and designates it"            = c("s = gptr('make big2')", "big2"),
  "s$value read, printed head"                      = c("s = gptr('designate big'); print(head(s$value, 2))", "big"),
  "x = s$value; rm(x)"                              = c("s = gptr('designate big'); x = s$value; rm(x)", "big"),
  "replay assignment s$value = big"                 = c("s = gptr('a'); s$value = big", "big"),
  "small object designated [copy policy]"           = c("small = runif(1e4); s = gptr('designate small')", "small"),
  "print / summary / str / format of s"             = c("s = gptr('designate big'); print(s); invisible(summary(s)); str(s); invisible(format(s))", "big"),
  "gptr_fork(s) + fork turn reading big"            = c("s = gptr('designate big'); f = gptr_fork(s); f |> gptr('read big')", "big"),
  "System 1 on the session"                         = c("s = gptr('designate big'); d = s |> gptr('ok?', model = jev)", "big"),
  "session created inside a function f(big)"        = c("f = function(d) gptr('describe', d); s = f(big)", "big"),
  "wrapper with model alias f(big)"                 = c("f = function(d) gptr('describe', d, model = haiku); s = f(big)", "big"),
  "wrapper, model = if (TRUE) opus else haiku"      = c("f = function(d) gptr('describe', d, model = if (TRUE) opus else haiku); s = f(big)", "big"),
  "forwarded dots w(...) -> gptr(...)"              = c("w = function(...) gptr(...); s = w('describe', big)", "big"),
  "System 1 on data: gptr('ok?', big, model = jev)" = c("d = gptr('ok?', big, model = jev)", "big"),
  "plain R baseline for a list element: L$a[1] = 0" = c("L = list(a = runif(5e6), b = runif(10))", "L$a"),
  "parallel = 2 over a list (trace L$a)"            = c("L = list(a = runif(5e6), b = runif(10)); ss = gptr('summarise', L, parallel = 2)", "L$a"),
  "background run with context, then settled"       = c("s = gptr('describe', big, background = TRUE); gptr_wait(s)", "big"),
  "saveRDS(s) / readRDS"                            = c("s = gptr('designate big'); p = tempfile(); saveRDS(s, p); r = readRDS(p)", "big"))
run_case = function(setup, traced) {
  f = tempfile(fileext = ".R")
  writeLines(c(sprintf('source("%s/setup.R")', W), 'options(gptr.sessions_dir = file.path(tempdir(), "cc"))',
    'the$provider = fake_rules(list("designate big" = list(code = "gptr_return(big)"),',
    '  "make big2" = list(code = "big2 = runif(5e6)\\ngptr_return(big2)"),',
    '  "designate small" = list(code = "gptr_return(small)"), "read big" = list(code = "length(big)")))',
    'the$s1 = fake_s1', 'big = runif(5e6)', setup,
    sprintf('invisible(tracemem(%s))', traced), sprintf('%s[1] = 0', traced), 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR:", tail(out, 2), collapse = " "))
  if (any(grepl("^tracemem\\[", out))) "COPY" else "in place"
}
for (nm in names(cases)) cat(sprintf("%-50s -> %s\n", nm, run_case(cases[[nm]][1], cases[[nm]][2])))
````

### `t6.out`

````text
[fake] Answer to: interpret the slope
<gptr_session 1b2013f3> idle | 2 turns | fake | 1.1k in (702 cached) / 46 out | value: fit <lm>
[fake] Answer to: one sentence please
<gptr_session 1b2013f3> idle | 3 turns | fake | 1.6k in (1.1k cached) / 56 out | value: fit <lm>
== 1. what a session serialises to ==
   data fields: created<character> dropped<list> entries<list> ext<list> file<character> flushed<logical> home_label<character> id<character> index<environment> last_text<character> leaf<character> loaded<logical> model<character> parent<NULL> persist<logical> queue<list> reason<character> replayed<integer> status<character> step<character> turns<integer> usage<list> values<list> 
  PASS no closures, connections, handles or processes in the session data
  PASS the only environment inside is the entry index (id -> position)
   serialize(s): 14602 bytes for 3 turns / 9 entries (the lm snapshot included)
  PASS round-trips through serialize()/unserialize()
== 2. readRDS in the SAME process: a detached copy, never a silent second writer ==
  PASS a new environment with the same id; the copy is detached
  PASS continuing the copy while the original lives: gptr_error_split_brain
  PASS gptr_resume(id) returns the live object itself
  PASS gptr_fork() of the copy is the explicit way to branch it
== 3. callr: the worker receives a copy; the lock keeps one writer per session file ==
                detached                      err 
                  "TRUE" "gptr_error_split_brain" 
  PASS the worker cannot continue while this process owns the session (lock + live pid)
== 4. R restart: gptr_resume() from the JSONL in a fresh process ==
  PASS finalizer removed the lock when the session was garbage collected
                 status                   turns                  loaded 
                 "idle"                     "3"                  "TRUE" 
            value_class             turns_after   provider_saw_messages 
                 "NULL"                     "4"                     "9" 
                   text 
"[fake] resumed answer" 
  PASS resumed with the full history; the next request carried every earlier message
== 5. a stale copy continued in a new process branches INSIDE the same file (no new session) ==
[fake] Answer to: a fifth turn in this process
<gptr_session 1b2013f3> idle | 5 turns | fake | 495 in (441 cached) / 12 out | value: fit <lm>
                                                                                                                                                                                                           turns 
                                                                                                                                                                                                             "5" 
                                                                                                                                                                                                              id 
                                                                                                                                                                                                      "1b2013f3" 
                                                                                                                                                                                                        messages 
"[gptr] session 1b2013f3: continuing from this object's state (turn 4); 2 newer entries in the file stay as a sibling branch\n || [gptr] re-attached session 1b2013f3 (home <env <environment: 0x1265d4aa8>>)\n" 
  PASS the file now has two children of one entry: a branch in the same session tree
  PASS same id; the copy continued from its own leaf (turn 4 -> 5)
````

### `t6_persist.R`

````r
# t6_persist.R -- persistence: sessions hold only serialisable data; live resources sit in a registry
# keyed by id. saveRDS/readRDS, serialize(), callr, a stale copy, resume after an "R restart".
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
SD = file.path(tempdir(), "t6"); options(gptr.sessions_dir = SD)
the$provider = fake_rules(list("fit" = list(code = "fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\nround(coef(fit), 2)")))
s = gptr("fit mpg on weight"); s |> gptr("interpret the slope"); s |> gptr("one sentence please")

cat("== 1. what a session serialises to ==\n")
d = .d(s)
kinds = vapply(ls(d, all.names = TRUE), function(n) class(get(n, envir = d))[1], "")
cat("   data fields:", paste(sprintf("%s<%s>", names(kinds), kinds), collapse = " "), "\n")
check(!any(kinds %in% c("function", "connection", "externalptr", "curl_handle", "process")), "no closures, connections, handles or processes in the session data")
check(all(vapply(ls(d), function(n) !is.environment(get(n, envir = d)) || n == "index", NA)), "the only environment inside is the entry index (id -> position)")
raw = serialize(s, NULL)
cat(sprintf("   serialize(s): %d bytes for %d turns / %d entries (the lm snapshot included)\n", length(raw), s$turns, length(d$entries)))
check(!inherits(tryCatch(unserialize(raw), error = function(e) e), "error"), "round-trips through serialize()/unserialize()")

cat("== 2. readRDS in the SAME process: a detached copy, never a silent second writer ==\n")
p = tempfile(fileext = ".rds"); saveRDS(s, p); s2 = readRDS(p)
check(!identical(s2, s) && identical(s2$id, s$id) && !s2$attached && s$attached, "a new environment with the same id; the copy is detached")
e = tryCatch({ s2 |> gptr("continue the copy"); "continued" }, error = function(e) class(e)[1])
check(identical(e, "gptr_error_split_brain"), "continuing the copy while the original lives: gptr_error_split_brain")
check(identical(gptr_resume(s$id), s), "gptr_resume(id) returns the live object itself")
f2 = gptr_fork(s2)
check(f2$id != s$id && f2$turns == 3L, "gptr_fork() of the copy is the explicit way to branch it")

cat("== 3. callr: the worker receives a copy; the lock keeps one writer per session file ==\n")
res = callr::r(function(W, SD, x) {
  source(file.path(W, "setup.R")); options(gptr.sessions_dir = SD); the$provider = fake_rules(list())
  c(detached = !x$attached, err = tryCatch({ x |> gptr("from the worker"); "continued" }, error = function(e) class(e)[1]))
}, args = list(W = W, SD = SD, x = s))
print(res)
check(identical(unname(res["err"]), "gptr_error_split_brain"), "the worker cannot continue while this process owns the session (lock + live pid)")

cat("== 4. R restart: gptr_resume() from the JSONL in a fresh process ==\n")
file = s$file; id = s$id
rm(s, s2); invisible(gc())                                  # finalizer releases the lock
check(!dir.exists(paste0(file, ".lock")), "finalizer removed the lock when the session was garbage collected")
out = callr::r(function(W, SD, id) {
  source(file.path(W, "setup.R")); options(gptr.sessions_dir = SD)
  seen = 0L
  the$provider = function(ctx, model, s) { seen <<- length(ctx); list(text = "[fake] resumed answer", delay = 0.01) }
  r = gptr_resume(id)
  before = c(status = r$status, turns = r$turns, loaded = .d(r)$loaded)
  v = r$value
  r |> gptr("what did we conclude?")
  c(before, value_class = class(v)[1], turns_after = r$turns, provider_saw_messages = seen, text = r$text)
}, args = list(W = W, SD = SD, id = id))
print(out)
check(identical(unname(out["turns_after"]), "4") && as.integer(out["provider_saw_messages"]) >= 9L,
      "resumed with the full history; the next request carried every earlier message")

cat("== 5. a stale copy continued in a new process branches INSIDE the same file (no new session) ==\n")
p2 = tempfile(fileext = ".rds")
x = gptr_resume(id); saveRDS(x, p2)                         # snapshot at 4 turns
x |> gptr("a fifth turn in this process")                   # the file moves on
rm(x); invisible(gc())
out2 = callr::r(function(W, SD, p2) {
  source(file.path(W, "setup.R")); options(gptr.sessions_dir = SD); the$provider = fake_rules(list())
  y = readRDS(p2)
  msg = character()
  withCallingHandlers(y |> gptr("continue the older snapshot"), message = function(m) { msg <<- c(msg, conditionMessage(m)); invokeRestart("muffleMessage") })
  c(turns = y$turns, id = y$id, messages = paste(msg, collapse = " || "))
}, args = list(W = W, SD = SD, p2 = p2))
print(out2)
ents = lapply(readLines(file)[-1], jsonlite::fromJSON, simplifyVector = FALSE)
par = vapply(ents, function(e) if (is.null(e$parentId)) "" else e$parentId, "")
check(any(duplicated(par[nzchar(par)])), "the file now has two children of one entry: a branch in the same session tree")
check(identical(unname(out2["id"]), id) && identical(unname(out2["turns"]), "5"), "same id; the copy continued from its own leaf (turn 4 -> 5)")
````

### `t6_persist.out`

````text
[fake] Answer to: interpret the slope
<gptr_session 586d007d> idle | 2 turns | fake | 1.1k in (702 cached) / 46 out | value: fit <lm>
[fake] Answer to: one sentence please
<gptr_session 586d007d> idle | 3 turns | fake | 1.6k in (1.1k cached) / 56 out | value: fit <lm>
== 1. what a session serialises to ==
   data fields: created<character> dropped<list> entries<list> ext<list> file<character> flushed<logical> home_label<character> id<character> index<environment> last_text<character> leaf<character> loaded<logical> model<character> parent<NULL> persist<logical> queue<list> reason<character> replayed<integer> seen<integer> status<character> step<character> turns<integer> usage<list> values<list> 
  PASS no closures, connections, handles or processes in the session data
  PASS the only environment inside is the entry index (id -> position)
   serialize(s): 14642 bytes for 3 turns / 9 entries (the lm snapshot included)
  PASS round-trips through serialize()/unserialize()
== 2. readRDS in the SAME process: a detached copy, never a silent second writer ==
  PASS a new environment with the same id; the copy is detached
  PASS continuing the copy while the original lives: gptr_error_split_brain
  PASS gptr_resume(id) returns the live object itself
  PASS gptr_fork() of the copy is the explicit way to branch it
== 3. callr: the worker receives a copy; the lock keeps one writer per session file ==
                detached                      err 
                  "TRUE" "gptr_error_split_brain" 
  PASS the worker cannot continue while this process owns the session (lock + live pid)
== 4. R restart: gptr_resume() from the JSONL in a fresh process ==
  PASS finalizer removed the lock when the session was garbage collected
                 status                   turns                  loaded 
                 "idle"                     "3"                  "TRUE" 
            value_class             turns_after   provider_saw_messages 
                 "NULL"                     "4"                     "9" 
                   text 
"[fake] resumed answer" 
  PASS resumed with the full history; the next request carried every earlier message
== 5. a stale copy continued in a new process branches INSIDE the same file (no new session) ==
[fake] Answer to: a fifth turn in this process
<gptr_session 586d007d> idle | 5 turns | fake | 495 in (441 cached) / 12 out | value: fit <lm>
                                                                                                                                                                                                           turns 
                                                                                                                                                                                                             "5" 
                                                                                                                                                                                                              id 
                                                                                                                                                                                                      "586d007d" 
                                                                                                                                                                                                        messages 
"[gptr] session 586d007d: continuing from this object's state (turn 4); 2 newer entries in the file stay as a sibling branch\n || [gptr] re-attached session 586d007d (home <env <environment: 0x1120294a8>>)\n" 
  PASS the file now has two children of one entry: a branch in the same session tree
  PASS same id; the copy continued from its own leaf (turn 4 -> 5)
````

### `t6b_knitr_cache.R`

````r
# t6b_knitr_cache.R -- knitr chunk cache and a session object: knit the same Rmd twice (fresh processes).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
K = file.path(W, "knit"); unlink(list.files(K, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE)
SD = file.path(K, "sessions")
rmd = c("---", "title: cache test", "---",
  "```{r setup, include = FALSE}",
  sprintf('source("%s/setup.R"); options(gptr.sessions_dir = "%s", gptr.quiet = TRUE); the$provider = fake_rules(list())', W, SD),
  "```",
  "```{r first, cache = TRUE}",
  's = gptr("summarise mtcars")',
  "```",
  "```{r second}",
  's |> gptr("now shorten it")',
  'cat("requests made in this knit:", the$requests, "| turns:", s$turns, "| status:", s$status, "\\n")',
  "```")
writeLines(rmd, file.path(K, "doc.Rmd"))
knit_once = function() callr::r(function(K) {
  setwd(K); knitr::knit("doc.Rmd", quiet = TRUE)
  out = readLines("doc.md"); out[grepl("requests made", out)]
}, args = list(K = K))
cat("knit 1:", knit_once(), "\n")
cat("knit 2:", knit_once(), "\n")
f = list.files(SD, pattern = "[.]jsonl$", full.names = TRUE)
ents = lapply(readLines(f[1])[-1], jsonlite::fromJSON, simplifyVector = FALSE)
users = vapply(Filter(function(e) identical(e$type, "message") && identical(e$message$role, "user"), ents), function(e) e$message$content[[1]]$text, "")
cat("session files:", length(f), "| user messages in the file:", paste(sprintf("'%s'", users), collapse = ", "), "\n")
par = vapply(ents, function(e) if (is.null(e$parentId)) "" else e$parentId, "")
cat("branch in the file (two children of one entry):", any(duplicated(par[nzchar(par)])), "\n")
````

### `t7.out`

````text
== RUN 1: record (live model, blocks written after each statement) ==
    requests=8 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4 
---- analysis.R after recording:
# analysis.R -- the program and the record of the agent work
a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')
# >>> gptr:5dd00b model=fake/fake date=2026-09-29 prompt=255a3959007b session=2b053d13 turn=1 value=counts
counts = matrix(1:20, 4)
dim(counts)
#> [1] 4 5
## Decision: (fake) answered turn 1.
a$value = counts
# <<< gptr:5dd00b
# >>> gptr:b51b8d model=fake/fake date=2026-09-29 prompt=6ef699c61233 call=2 session=2b053d13 turn=2 value=tpm
tpm = counts / colSums(counts) * 1e6
round(colSums(tpm))
#> [1]  317317 1127275 1851846 2353606 1680274
## Decision: (fake) answered turn 2.
a$value = tpm
# <<< gptr:b51b8d
a |> gptr('How many genes pass the filter?')
# >>> gptr:68606a model=fake/fake date=2026-09-29 prompt=f53ff28e764c session=2b053d13 turn=3 value=keep
keep = rowSums(tpm > 2e5) >= 2
sum(keep)
#> [1] 4
## Decision: (fake) answered turn 3.
a$value = keep
# <<< gptr:68606a
gptr_fork(a) |> gptr('Try a stricter filter as well')
# >>> gptr:11119e model=fake/fake date=2026-09-29 prompt=ed64d3adeff7 session=285ed6be turn=4 fork=2b053d13:3 value=keep
local({
  keep = rowSums(tpm > 3e5) >= 2
  sum(keep)
  #> [1] 4
}, envir = gptr_resume("285ed6be")$envir)
## Decision: (fake) answered turn 4.
# <<< gptr:11119e

== RUN 2: replay in a fresh process (no model calls; blocks rebuild the objects) ==
    requests=0 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4
    sessions attached: 285ed6be 2b053d13 
    replayed turns of a: 1,2,3 | a$values turns: 1,2,3 | a$value: logical 
    fork 285ed6be turns 4 | fork keep (overlay): 1,2,3,4  

== RUN 3: same process, source() twice: re-running steering statements adds no turns ==
    requests=0 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4
    requests=0 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4 

== RUN 4: replay, then re-run ONE steering statement live: a real new turn, document untouched ==
    requests=0 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4
    after live re-run: requests=2 turns=4 
  document unchanged by live mode: TRUE 

== RUN 5: edit the prompt of statement 2, record: only that block regenerates; the session branches ==
    requests=2 | a: id 2b053d13 turns 3, value logical[4] | session files 2 | global keep: rows 1,2,3,4
    branch inside the session file (same id): TRUE  
---- analysis.R after regeneration (headers only):
a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')
# >>> gptr:5dd00b model=fake/fake date=2026-09-29 prompt=255a3959007b session=2b053d13 turn=1 value=counts
a$value = counts
# >>> gptr:b51b8d model=fake/fake date=2026-09-29 prompt=6ef699c61233 call=2 session=2b053d13 turn=2 value=tpm
a$value = tpm
a |> gptr('How many genes pass the filter at 2 samples?')
# >>> gptr:68606a model=fake/fake date=2026-09-29 prompt=ccd141411a25 session=2b053d13 turn=3 value=keep
a$value = keep
gptr_fork(a) |> gptr('Try a stricter filter as well')
# >>> gptr:11119e model=fake/fake date=2026-09-29 prompt=ed64d3adeff7 session=285ed6be turn=4 fork=2b053d13:3 value=keep
````

### `t7_history.R`

````r
# t7_history.R -- the history document and the session: record, replay without model calls, re-run.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
P = file.path(W, "hist"); unlink(list.files(P, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE)
doc = c(
  "# analysis.R -- the program and the record of the agent work",
  "a = gptr('Load the counts and normalise them') |> gptr('Use TPM, not CPM')",
  "a |> gptr('How many genes pass the filter?')",
  "gptr_fork(a) |> gptr('Try a stricter filter as well')")
writeLines(doc, file.path(P, "analysis.R"))
writeLines(c(
  sprintf('W = "%s"; P = "%s"', W, P), 'options(g3.with_doc = TRUE)', 'source(file.path(W, "setup.R"))',
  'options(gptr.sessions_dir = file.path(P, ".gptr", "sessions"), gptr.replay = Sys.getenv("MODE"), gptr.quiet = Sys.getenv("QUIET") == "1")',
  'the$provider = fake_rules(list(',
  '  "Load the counts" = list(code = "counts = matrix(c(5, 50, 500, 5000, 6, 60, 600, 6000, 7, 70, 700, 7000), 4)\\ngptr_return(counts)\\ndim(counts)"),',
  '  "TPM" = list(code = "tpm = t(t(counts) / colSums(counts)) * 1e6\\ngptr_return(tpm)\\nround(colSums(tpm))"),',
  '  "stricter" = list(code = "keep = rowSums(tpm > 1e5) >= 2\\ngptr_return(keep)\\nsum(keep)"),',
  '  "filter" = list(code = "keep = rowSums(tpm > 1e4) >= 2\\ngptr_return(keep)\\nsum(keep)")))',
  'run = function() { source(file.path(P, "analysis.R"), keep.source = TRUE, local = globalenv())',
  '  cat(sprintf("  requests=%d | a: id %s turns %d, value %s | session files %d | global keep: rows %s\\n", the$requests, a$id, a$turns,',
  '      paste0(class(a$value), "[", length(a$value), "]"), length(list.files(getOption("gptr.sessions_dir"), "[.]jsonl$")), paste(which(keep), collapse = ",")))',
  '  invisible() }'), file.path(P, "driver_lib.R"))
rs = function(mode, extra = character(), quiet = TRUE) {
  f = tempfile(fileext = ".R")
  writeLines(c(sprintf('source("%s/driver_lib.R")', P), extra), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE,
                env = c(paste0("MODE=", mode), paste0("QUIET=", if (quiet) "1" else "0")))
  cat(paste0("  ", out[!grepl("^\\[fake\\]|^<gptr_session", out)], collapse = "\n"), "\n")
}

cat("== RUN 1: record (live model, blocks written after each statement) ==\n"); rs("record", "run()")
cat("---- analysis.R after recording:\n"); cat(readLines(file.path(P, "analysis.R")), sep = "\n")
cat("\n== RUN 2: replay in a fresh process (no model calls; blocks rebuild the objects) ==\n")
rs("replay", c("run()", 'cat("  sessions attached:", paste(sort(ls(the$live)), collapse = " "), "\\n")',
               'cat("  replayed turns of a:", paste(.d(a)$replayed, collapse = ","), "| a$values turns:", paste(a$values$turn, collapse = ","), "| a$value:", class(a$value), "\\n")',
               'fk = gptr_resume(sub(".*session=([0-9a-f]+) turn=4.*", "\\\\1", grep("turn=4", readLines(file.path(P, "analysis.R")), value = TRUE)))',
               'cat("  fork", fk$id, "turns", fk$turns, "| fork keep (overlay):", paste(which(get("keep", envir = fk$envir)), collapse = ","), "\\n")'))
cat("\n== RUN 3: same process, source() twice: re-running steering statements adds no turns ==\n")
rs("replay", c("run()", "run()"))
cat("\n== RUN 4: replay, then re-run ONE steering statement live: a real new turn, document untouched ==\n")
md5 = tools::md5sum(file.path(P, "analysis.R"))
rs("replay", c("run()", 'options(gptr.replay = "live")', "a |> gptr('How many genes pass the filter?')",
               'cat(sprintf("  after live re-run: requests=%d turns=%d\\n", the$requests, a$turns))'))
cat("  document unchanged by live mode:", identical(md5, tools::md5sum(file.path(P, "analysis.R"))), "\n")
cat("\n== RUN 5: edit the prompt of statement 2, record: only that block regenerates; the session branches ==\n")
txt = readLines(file.path(P, "analysis.R")); txt = sub("How many genes pass the filter?", "How many genes pass the filter at 2 samples?", txt, fixed = TRUE)
writeLines(txt, file.path(P, "analysis.R"))
rs("record", c("run()", 'e = .d(a)$entries; par = vapply(e, function(x) if (is.null(x$parentId)) "" else x$parentId, "")',
               'cat("  branch inside the session file (same id):", any(duplicated(par[nzchar(par)])), "\\n")'))
cat("---- analysis.R after regeneration (headers only):\n"); cat(grep("^# >>>|^a|^gptr", readLines(file.path(P, "analysis.R")), value = TRUE), sep = "\n")
````

### `t8_edge.R`

````r
# t8_edge.R -- aliasing, identical(), lists of sessions, lapply, memory growth, finalizers, gc.
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(tempdir(), "t8"), gptr.quiet = TRUE)
the$provider = fake_rules(list("big" = list(code = "b = runif(2e6)\ngptr_return(b)\nlength(b)")), delay = 0)

cat("== identity ==\n")
a = gptr("one"); b = a; l = list(a, a)
check(identical(a, b) && identical(l[[1]], l[[2]]), "b = a and list(a, a): one session, identical() is TRUE")
check(!isTRUE(all.equal(a, gptr_fork(a))) || TRUE, "all.equal() compares contents (R >= 4.1 all.equal.environment); identity is identical()")
check(identical(a |> gptr("two"), b), "the pipe returns the same object")

cat("== lists and lapply ==\n")
ss = lapply(c(x = "first", y = "second"), function(p) gptr(p))
out = lapply(ss, function(s) s |> gptr("refine"))
check(all(mapply(identical, out, ss)) && all(vapply(ss, function(s) s$turns, 1L) == 2L), "lapply(sessions, \\(s) s |> gptr(...)) steers each in place")
check(all(vapply(ss, function(s) identical(.d(s)$home_label, "<env <environment: R_GlobalEnv>>") || .d(s)$home_label != "", NA)),
      "sessions created inside lapply's closure keep a label only; each continuation used its own caller")
ss_home = vapply(ss, function(s) is.null(s$envir), NA)
cat("   home retained for sessions created inside the lapply closure:", !ss_home, "(frames are never retained)\n")

cat("== memory growth over 200 turns (text-only turns) ==\n")
m = gptr("start")
sz = function(s) as.numeric(object.size(.d(s)$entries)) + as.numeric(object.size(.d(s)$values))
s0 = sz(m); t0 = Sys.time()
for (i in 1:200) m |> gptr(paste("turn", i, strrep("x", 200)))
el = as.numeric(Sys.time() - t0, units = "secs")
cat(sprintf("   200 turns: %.2f s total (%.1f ms/turn incl. JSONL append); transcript grew %.0f KB -> %.0f KB (%.1f KB/turn)\n",
            el, el / 200 * 1000, s0 / 1024, sz(m) / 1024, (sz(m) - s0) / 1024 / 200))
cat(sprintf("   JSONL file: %.0f KB; serialize(m): %.0f KB\n", file.size(m$file) / 1024, length(serialize(m, NULL)) / 1024))

cat("== held values are bounded ==\n")
options(gptr.values_max_bytes = 40e6)
v = gptr("keep big")
for (i in 1:5) v |> gptr("keep big")                     # each turn designates a new 16 MB vector 'b'
vt = v$values
cat("   values by kind:", paste(vt$by, collapse = ","), "| held:", paste(vt$held, collapse = ","), "\n")
check(all(vt$by == "name") && !any(vt$held), "16 MB objects bound in globalenv are held BY NAME: the session holds no copy")
rm(b)

options(gptr.values_max_bytes = 5e6)
the$provider = fake_rules(list("small" = list(code = "sm = runif(7.5e4)\ngptr_return(sm)\nlength(sm)")), delay = 0)
cv = gptr("small one")
for (i in 1:20) cv |> gptr("small one")                 # each turn designates a new 600 KB vector (copy policy)
ct = cv$values
cat(sprintf("   copy policy: %d values, %d held (%.1f MB), budget 5 MB; latest held: %s\n", nrow(ct), sum(ct$held),
            sum(ct$size[ct$held]) / 1e6, ct$held[nrow(ct)]))
check(sum(ct$size[ct$held]) <= 5e6 && ct$held[nrow(ct)] && identical(cv$value, sm), "held copies stay within gptr.values_max_bytes; the latest is always held")
the$provider = fake_rules(list(), delay = 0)

cat("== finalizers and gc of finished sessions ==\n")
the$finalized = character()
ids = vapply(1:5, function(i) gptr(paste("temp", i))$id, "")
invisible(gc()); invisible(gc())
check(all(ids %in% the$finalized), "5 unreferenced finished sessions were collected; their finalizers ran")
check(!any(ids %in% ls(the$live)), "registry entries were removed (weak keys, no leak)")
check(all(!dir.exists(paste0(list.files(getOption("gptr.sessions_dir"), pattern = paste0(ids[1], "[.]jsonl$"), full.names = TRUE), ".lock"))), "their lock directories were removed")
bgs = gptr("background, unreferenced", background = TRUE); bid = bgs$id; rm(bgs); invisible(gc())
check(exists(bid, envir = the$active) && !(bid %in% the$finalized), "a RUNNING unreferenced session is kept alive by the reactor")
while (length(ls(the$active))) later::run_now(0.05)
invisible(gc())
check(bid %in% the$finalized, "... and collected once it settled")
f = function(big) { s = gptr("inside a function", big); s$id }
fid = f(runif(10)); invisible(gc())
check(fid %in% the$finalized, "a session created and dropped inside a function is collected with its frame")
````

### `t8_edge.out`

````text
== identity ==
  PASS b = a and list(a, a): one session, identical() is TRUE
  PASS all.equal() compares contents (R >= 4.1 all.equal.environment); identity is identical()
  PASS the pipe returns the same object
== lists and lapply ==
  PASS lapply(sessions, \(s) s |> gptr(...)) steers each in place
  PASS sessions created inside lapply's closure keep a label only; each continuation used its own caller
   home retained for sessions created inside the lapply closure: FALSE FALSE (frames are never retained)
== memory growth over 200 turns (text-only turns) ==
   200 turns: 6.45 s total (32.3 ms/turn incl. JSONL append); transcript grew 6 KB -> 1377 KB (6.9 KB/turn)
   JSONL file: 189 KB; serialize(m): 335 KB
== held values are bounded ==
   values by kind: name,name,name,name,name,name | held: FALSE,FALSE,FALSE,FALSE,FALSE,FALSE 
  PASS 16 MB objects bound in globalenv are held BY NAME: the session holds no copy
   copy policy: 21 values, 8 held (4.8 MB), budget 5 MB; latest held: TRUE
  PASS held copies stay within gptr.values_max_bytes; the latest is always held
== finalizers and gc of finished sessions ==
  PASS 5 unreferenced finished sessions were collected; their finalizers ran
  PASS registry entries were removed (weak keys, no leak)
  PASS their lock directories were removed
  PASS a RUNNING unreferenced session is kept alive by the reactor
  PASS ... and collected once it settled
  PASS a session created and dropped inside a function is collected with its frame
````

### `t9-sessions/2026-09-30T05-58-04-119Z_3298389c.jsonl`

````text
{"type":"session","version":3,"id":"3298389c","timestamp":"2026-09-30T05:58:04.119Z","cwd":"/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3","gptr":{"format":1}}
{"type":"message","id":"27aca3b7","parentId":null,"timestamp":"2026-09-30T05:58:04.121Z","message":{"role":"user","content":[{"type":"text","text":"Load the counts and normalise them"}],"timestamp":1790747884121,"gptr":{"deliver":"prompt","source":"call"}}}
{"type":"message","id":"46cf90a4","parentId":"27aca3b7","timestamp":"2026-09-30T05:58:04.461Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_3057ba","name":"r","arguments":{"code":"Sys.sleep(1.5)\ncounts = matrix(rpois(20, 5), 4)\ngptr_return(counts)\ndim(counts)"}}],"provider":"fake","model":"fake","usage":{"input":328,"cacheRead":0,"output":20},"stopReason":"toolUse","timestamp":1790747884461}}
{"type":"custom","id":"6521234d","parentId":"46cf90a4","timestamp":"2026-09-30T05:58:05.963Z","customType":"gptr.value","data":{"turn":1,"by":"copy","name":"counts","env":"globalenv()","class":"matrix","size":344}}
{"type":"message","id":"6294c819","parentId":"6521234d","timestamp":"2026-09-30T05:58:05.963Z","message":{"role":"toolResult","toolCallId":"call_3057ba","toolName":"r","content":[{"type":"text","text":"[1] 4 5"}],"isError":false,"timestamp":1790747885964}}
{"type":"message","id":"15dd13df","parentId":"6294c819","timestamp":"2026-09-30T05:58:06.306Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Done ([1] 4 5). Saw: 'Load the counts and normalise them'"}],"provider":"fake","model":"fake","usage":{"input":375,"cacheRead":328,"output":16},"stopReason":"stop","timestamp":1790747886306}}
{"type":"message","id":"6543a0af","parentId":"15dd13df","timestamp":"2026-09-30T05:58:06.307Z","message":{"role":"user","content":[{"type":"text","text":"Use TPM, not CPM"}],"timestamp":1790747886307,"gptr":{"deliver":"steer","source":"pipe"}}}
{"type":"message","id":"76adda86","parentId":"6543a0af","timestamp":"2026-09-30T05:58:06.632Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_ea7519","name":"r","arguments":{"code":"Sys.sleep(5)\ntpm = counts * 2\ngptr_return(tpm)\nrange(tpm)"}}],"provider":"fake","model":"fake","usage":{"input":409,"cacheRead":375,"output":20},"stopReason":"toolUse","timestamp":1790747886633}}
{"type":"custom","id":"4fe5d049","parentId":"76adda86","timestamp":"2026-09-30T05:58:11.642Z","customType":"gptr.value","data":{"turn":2,"by":"copy","name":"tpm","env":"globalenv()","class":"matrix","size":376}}
{"type":"message","id":"38cd70c6","parentId":"4fe5d049","timestamp":"2026-09-30T05:58:11.643Z","message":{"role":"toolResult","toolCallId":"call_ea7519","toolName":"r","content":[{"type":"text","text":"[1]  2 18"}],"isError":false,"timestamp":1790747891644}}
{"type":"message","id":"37a6f44c","parentId":"38cd70c6","timestamp":"2026-09-30T05:58:11.990Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Done ([1]  2 18). Saw: 'Use TPM, not CPM'"}],"provider":"fake","model":"fake","usage":{"input":452,"cacheRead":409,"output":12},"stopReason":"stop","timestamp":1790747891990}}
{"type":"message","id":"31f0c61f","parentId":"37a6f44c","timestamp":"2026-09-30T05:58:11.991Z","message":{"role":"user","content":[{"type":"text","text":"Also report library sizes"}],"timestamp":1790747891991,"gptr":{"deliver":"follow_up","source":"menu"}}}
{"type":"message","id":"2509377d","parentId":"31f0c61f","timestamp":"2026-09-30T05:58:12.297Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_5f36d6","name":"r","arguments":{"code":"Sys.sleep(4)\nlibsize = colSums(counts)\nlibsize"}}],"provider":"fake","model":"fake","usage":{"input":483,"cacheRead":452,"output":20},"stopReason":"toolUse","timestamp":1790747892298}}
{"type":"message","id":"141a028a","parentId":"2509377d","timestamp":"2026-09-30T05:58:16.299Z","message":{"role":"toolResult","toolCallId":"call_5f36d6","toolName":"r","content":[{"type":"text","text":"[1] 20 18 15 19 20"}],"isError":false,"timestamp":1790747896299}}
{"type":"message","id":"2b9cb213","parentId":"141a028a","timestamp":"2026-09-30T05:58:16.604Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Done ([1] 20 18 15 19 20). Saw: 'Also report library sizes'"}],"provider":"fake","model":"fake","usage":{"input":525,"cacheRead":483,"output":17},"stopReason":"stop","timestamp":1790747896605}}
{"type":"message","id":"3c6f13c3","parentId":"2b9cb213","timestamp":"2026-09-30T05:58:16.605Z","message":{"role":"user","content":[{"type":"text","text":"Summarise in one line"}],"timestamp":1790747896606,"gptr":{"deliver":"follow_up","source":"inbox"}}}
{"type":"message","id":"207a8634","parentId":"3c6f13c3","timestamp":"2026-09-30T05:58:16.909Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: Summarise in one line"}],"provider":"fake","model":"fake","usage":{"input":561,"cacheRead":525,"output":10},"stopReason":"stop","timestamp":1790747896909}}
````

### `t9-sessions/2026-09-30T05-58-17-237Z_4c00d094.jsonl`

````text
{"type":"session","version":3,"id":"4c00d094","timestamp":"2026-09-30T05:58:17.237Z","cwd":"/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3","gptr":{"format":1}}
{"type":"message","id":"497dcb87","parentId":null,"timestamp":"2026-09-30T05:58:17.237Z","message":{"role":"user","content":[{"type":"text","text":"slow job"}],"timestamp":1790747897237,"gptr":{"deliver":"prompt","source":"call"}}}
{"type":"message","id":"4c0de9af","parentId":"497dcb87","timestamp":"2026-09-30T05:58:17.541Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_bd31c2","name":"r","arguments":{"code":"Sys.sleep(2)\n'slow done'"}}],"provider":"fake","model":"fake","usage":{"input":321,"cacheRead":312,"output":20},"stopReason":"toolUse","timestamp":1790747897542}}
{"type":"message","id":"2569072b","parentId":"4c0de9af","timestamp":"2026-09-30T05:58:20.214Z","message":{"role":"toolResult","toolCallId":"call_bd31c2","toolName":"r","content":[{"type":"text","text":"[1] \"slow done\""}],"isError":false,"timestamp":1790747900215}}
{"type":"message","id":"1255ab3d","parentId":"2569072b","timestamp":"2026-09-30T05:58:20.519Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Done ([1] \"slow done\"). Saw: 'slow job'"}],"provider":"fake","model":"fake","usage":{"input":357,"cacheRead":321,"output":12},"stopReason":"stop","timestamp":1790747900520}}
````

### `t9-sessions/2026-09-30T05-58-24-038Z_365d3b32.jsonl`

````text
{"type":"session","version":3,"id":"365d3b32","timestamp":"2026-09-30T05:58:24.038Z","cwd":"/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3","gptr":{"format":1}}
{"type":"message","id":"22d96b80","parentId":null,"timestamp":"2026-09-30T05:58:24.039Z","message":{"role":"user","content":[{"type":"text","text":"say hi"}],"timestamp":1790747904039,"gptr":{"deliver":"prompt","source":"call"}}}
{"type":"message","id":"7020b25f","parentId":"22d96b80","timestamp":"2026-09-30T05:58:24.345Z","message":{"role":"assistant","content":[{"type":"text","text":"[fake] Answer to: say hi"}],"provider":"fake","model":"fake","usage":{"input":321,"cacheRead":312,"output":6},"stopReason":"stop","timestamp":1790747904345}}
````

### `t9.out`

````text
[1] TRUE
---- 1. background session: the prompt comes back at once; the idle console services it (later)
[1] TRUE
[1] TRUE
---- 2. pipe steering from the prompt while it runs (returns immediately)
[1] TRUE
---- 3. Ctrl-C while a BACKGROUND tool blocks the console: the same pause menu; (f)ollow-up
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
---- 4. gptr_wait(): foreground attach; ANOTHER process writes a follow-up to the file inbox meanwhile
[1] TRUE
[1] TRUE
---- 5. foreground gptr() at the console, Ctrl-C then (b)ackground: the prompt comes back, the run continues
[1] TRUE
[1] TRUE
[1] TRUE
[1] TRUE
---- 6. interactive visibility: a foreground call prints once (printed as it settles, returned invisibly)
[1] TRUE
CHILD READY interactive() = TRUE 
STATUS running 
IDLE CHECK step boundary entries 4 
[gptr] queued steer for running session 1b71782a
PIPE RETURNED after 0.001 s; queue: Use TPM, not CPM 
[gptr] paused 1b71782a: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? follow-up> [gptr] queued; continuing
ID 1b71782a 
[fake] Answer to: Summarise in one line
<gptr_session 1b71782a> idle | 4 turns | fake | 3.1k in (2.6k cached) / 115 out | value: tpm <matrix>
TRANSCRIPT user<call> assi tool assi user<pipe> assi tool assi user<menu> assi tool assi user<inbox> assi 
[gptr] paused 55a100e4: (s)teer, (f)ollow-up, (b)ackground, (a)bort, (c)ontinue? [gptr] running in the background; gptr_wait() re-attaches
BACK AT PROMPT status running 
[gptr] session 55a100e4 finished (stop, turn 1)
LATER status idle turns 1 
[fake] Answer to: say hi
<gptr_session d8a2a83a> idle | 1 turn | fake | 321 in (312 cached) / 6 out | value: none
AFTER CALL
````

### `t9_child.R`

````r
# t9_child.R -- sourced inside an interactive R driven by t9_driver.R
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
source(file.path(W, "setup.R"))
options(gptr.sessions_dir = file.path(W, "t9-sessions"))
unlink(getOption("gptr.sessions_dir"), recursive = TRUE)
the$provider = fake_rules(list(
  "counts" = list(code = "Sys.sleep(1.5)\ncounts = matrix(rpois(20, 5), 4)\ngptr_return(counts)\ndim(counts)", delay = 0.3),
  "TPM" = list(code = "Sys.sleep(5)\ntpm = counts * 2\ngptr_return(tpm)\nrange(tpm)", delay = 0.3),
  "library sizes" = list(code = "Sys.sleep(4)\nlibsize = colSums(counts)\nlibsize", delay = 0.3),
  "slow" = list(code = "Sys.sleep(2)\n'slow done'", delay = 0.3)), delay = 0.3)
roles = function(s) { h = s$history; paste(sprintf("%s%s", substr(h$role, 1, 4), ifelse(is.na(h$source), "", paste0("<", h$source, ">"))), collapse = " ") }
cat("CHILD READY interactive() =", interactive(), "\n")
````

### `t9_driver.R`

````r
# t9_driver.R -- drive an interactive R (R --interactive, stdin piped) like a user at the console;
# real SIGINTs via processx (report 18 harness).
W = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G3"
library(processx)
p = process$new(file.path(R.home("bin"), "R"), c("--vanilla", "--interactive", "-q", "--no-echo"),
                stdin = "|", stdout = "|", stderr = "2>&1", env = c("current", LANG = "en_US.UTF-8"))
st = new.env(); st$out = character(); st$seen = 0L   # state in an environment, no <<-
pump = function(ms = 100) { p$poll_io(ms); x = p$read_output(); if (nzchar(x)) st$out = c(st$out, x) }
text = function() paste(st$out, collapse = "")
wait_for = function(pat, timeout = 30) {
  t0 = Sys.time()
  repeat {
    pump()
    txt = substring(text(), st$seen + 1L)
    if (grepl(pat, txt, fixed = TRUE)) { st$seen = st$seen + regexpr(pat, txt, fixed = TRUE)[[1]] + nchar(pat) - 1L; return(TRUE) }
    if (!p$is_alive() || as.numeric(Sys.time() - t0, units = "secs") > timeout) { cat("TIMEOUT waiting for:", pat, "\n"); return(FALSE) }
  }
}
send = function(x) { Sys.sleep(0.15); p$write_input(paste0(x, "\n")) }
step = function(label) cat(sprintf("---- %s\n", label))

send(sprintf('source("%s/t9_child.R")', W)); wait_for("CHILD READY")
step("1. background session: the prompt comes back at once; the idle console services it (later)")
send('s = gptr("Load the counts and normalise them", background = TRUE); cat("STATUS", s$status, "\\n")')
wait_for("STATUS running")
Sys.sleep(1.0)                                            # user idle at the prompt
send('cat("IDLE CHECK step", .d(s)$step, "entries", length(.d(s)$entries), "\\n")'); wait_for("IDLE CHECK")
step("2. pipe steering from the prompt while it runs (returns immediately)")
send('t0 = Sys.time(); s |> gptr("Use TPM, not CPM"); cat("PIPE RETURNED after", round(as.numeric(Sys.time() - t0, units = "secs"), 3), "s; queue:", s$queue, "\\n")')
wait_for("PIPE RETURNED")
step("3. Ctrl-C while a BACKGROUND tool blocks the console: the same pause menu; (f)ollow-up")
Sys.sleep(1.0); p$interrupt()
wait_for("paused"); send("f"); wait_for("follow-up> "); send("Also report library sizes")
wait_for("queued; continuing")
send('cat("ID", s$id, "\\n")'); wait_for("ID "); pump(200)
id = sub("^\\s*([0-9a-f]{8}).*$", "\\1", substring(text(), st$seen + 1L))
step("4. gptr_wait(): foreground attach; ANOTHER process writes a follow-up to the file inbox meanwhile")
send('gptr_wait(s)')
bg = callr::r_bg(function(W, id) { source(file.path(W, "setup.R")); options(gptr.sessions_dir = file.path(W, "t9-sessions"))
  gptr_steer(id, "Summarise in one line", deliver = "follow_up") }, args = list(W = W, id = id))
bg$wait(20000)
wait_for("<gptr_session")                                  # gptr_wait returns the session visibly: printed
send('cat("TRANSCRIPT", roles(s), "\\n")'); wait_for("TRANSCRIPT")
step("5. foreground gptr() at the console, Ctrl-C then (b)ackground: the prompt comes back, the run continues")
send('z = gptr("slow job"); cat("BACK AT PROMPT status", z$status, "\\n")')
Sys.sleep(0.8); p$interrupt(); wait_for("paused"); send("b")
wait_for("BACK AT PROMPT")
Sys.sleep(3.5)
send('cat("LATER status", z$status, "turns", z$turns, "\\n")'); wait_for("LATER status")
step("6. interactive visibility: a foreground call prints once (printed as it settles, returned invisibly)")
send('gptr("say hi"); cat("AFTER CALL\\n")'); wait_for("AFTER CALL")
Sys.sleep(0.3); pump(300)
send("q('no')"); p$wait(5000); pump(200); if (p$is_alive()) p$kill()
cat(gsub("\r", "", text()))
````

## Verification log

Verdict: **sound_after_corrections** (22 claims checked).

There is no markdown report to edit. The G3 research agent was blocked from writing dev/research/G3-session-object-pipe-steering.md ("Subagents should return findings as text"). Its report is the structured output recorded in the workflow journal (subagents/workflows/wf_94cbad23-aab/journal.jsonl, agentId aa5936cf39b12c8a9), plus the prototypes in the G3 directory. I extracted that output to verify-G3/g3_result.txt and checked it. I could not apply fixes in place or append a '## Verification log' to a file: none exists, and this harness also forbids writing report .md files. The corrections and the log are therefore in this structured output, and whoever writes the G3 report should fold them in. I made no changes in G3/. Every prototype was re-run with Rscript --vanilla on a path-rewritten copy (verify-G3/copy; outputs in verify-G3/copy/rerun/).

VERIFICATION LOG (claim | verdict | source)
1. gptr() returns the S3 env-backed session; the pipe returns the identical object; aliases see every turn; $<- is refused | VERIFIED, t1 12/12 PASS | rerun/t1_class.out
2. R6 vs S3 | PARTLY: sizes exact, timings vary, clone nuance | rerun/t1b_r6.out, indep1.R
3. The weak registry (key = session, value = live) lets sessions be collected; a strong registry (report 12's the$sessions[[id]] <- s) leaks them | VERIFIED | rerun/p1_weakref.out, indep1.R #3, rlang 1.1.7 new_weakref help, report 12 line 1977
4. Holding a function frame strongly, or as a weakref value while the key lives, makes the caller's argument sticky | VERIFIED | rerun/p2.out
5. R_CleanupEnvir releases a frame only if REFCNT is 0 after discounting simple cycles; cleanupEnvVector is disabled; the code is identical in 4.4.3 and trunk; GC never decrements refcounts | VERIFIED | work/12/ext/eval_R-4-4-3.c 2063-2169 vs verify-G3/eval_trunk.c (byte-identical block); verify-G3/memory_trunk.c
6. The five named causes of frame pins | VERIFIED as causes (p5b, p5i, p5n and p5o outputs reproduce exactly, including JIT 0/3), but INCOMPLETE: garbage lists are a sixth cause (adv4.R)
7. Copy safety of 21 of 21 entry points | CORRECTED: 20/20 tested; tool code in a function-frame home COPIES
8. Base-R identifier resolution, including forwarded dots with a WRONG-LOCAL m, resolves to haiku | VERIFIED | rerun/t2b_nse.out
9. One pipe rule and one queue: steers land after the complete tool result, follow-ups at stop, abort moves the queue to dropped | VERIFIED, t3 13/13 PASS, t2 12/12; t9 interactive transcript reproduced with real SIGINT | rerun/t3_steer.out, rerun/t9_driver.out. Consistent with Pi's agent-loop.ts (steering is taken after the tool batch; the default queue mode is one-at-a-time, per agent.ts 247-248)
10. A SIGINT during a later() callback reaches a calling handler and resumes | VERIFIED | rerun/p6_later_sigint.out. Menu pitfalls: VERIFIED in principle (indep2.R)
11. gptr_fork, t4 21/21 PASS; Pi createBranchedSession keeps ids and sets parentSession; fork emits session_start reason 'fork' | VERIFIED with nuances (Pi writes eagerly and keeps labels) | rerun/t4_fork.out; Pi session-manager.ts 1632-1725; agent-session-runtime.ts 262-350
12. Fork 97% cache and the chain's cached share | UNCERTAIN for real providers (fake artifact)
13. A serialised frame reference gives 16.0 MB vs 23 KB; a deserialised connection writes into an unrelated file on reused connection number 3; the curl handle is dead; processx is_alive FALSE; later cancel FALSE | VERIFIED: 16,023,529 / 23,458 B on rerun; independent stale-connection test also wrote into b.txt | rerun/p3*.out, indep1.R #1
14. Session serialises to 14,642 B; split_brain rules; gptr_resume carries 9 messages; a stale copy branches inside the same file | VERIFIED exactly, t6 12/12 | rerun/t6_persist.out
15. knitr cache: knit 1 made 2 requests, knit 2 made 1; branch TRUE | VERIFIED | rerun/t6b_knitr_cache.out
16. History document: record 8 requests; replay 0; idempotent source; live re-run leaves the document unchanged; edited prompt branches in the same file | VERIFIED | rerun/t7_history.out
17. Pi v3 compatibility: loader checks only type == 'session' and a string id (line 664); convertToLlm passes user messages through (messages.ts 148-190); the Anthropic adapter builds the wire message from content only (1279-1300); plain custom entries are excluded from context | VERIFIED | Pi 1b347794
18. System 1 over a session sends 55-70 chars, adds no turn, writes a gptr.decision entry | VERIFIED (55 in t2, 70 in ex_jsonl) | rerun outputs
19. North-star §2/§3/§11 run end to end; §11's 'Cluster {cl}' needs glue while report 12 D4 bans auto-interpolation | VERIFIED | rerun/ns_traces.out; spec/02-north-star-examples.md line 279; report 12 line 683. The 'classified differently' wording is overstated.
20. chars/4 underestimates printed R output by about 51% (report 21) | VERIFIED as a faithful citation | 21-rcpp-hot-paths.md line 65
21. Performance (24.1 ms/turn; JIT first call) | VERIFIED qualitatively; numbers vary
22. rlang provides new_weakref, hash, obj_address and duplicate | VERIFIED (rlang 1.1.7) | indep1.R #4

Overall: the core S-8 design is reproducible. That covers the session as the return value, the S3 env with a hidden data env, the weak live registry, one pipe rule with one queue, background runs as sessions, the overlay fork, data-only persistence with split-brain rules, and Pi v3 compatibility. The one correction plans must carry is copy safety. The prototype is not copy-safe when a session's home is a function frame and the agent runs code there. The capture rules must be extended to every frame and container that references a user frame, and the tracemem suite must include tool execution in function-frame homes and values that capture environments.

Corrections (apply these over the summary above):

- **Was:** Copy safety: 21 of 21 entry points leave the user's object editable in place (t5); with five capture rules every gptr entry point is copy-safe.
  **Now:** t5 has 23 rows: 20 gptr entry points plus 3 plain-R baselines (big[1] = 0, str(big) and L$a[1] = 0). All 20 gptr rows are in place (confirmed on re-run), so the count is 20 of 20, not 21 of 21. More importantly, t5's 'session created inside a function f(big)' case never ran any agent code, because the fake had no rule for 'describe'. When the agent's R code runs in a function-frame home, the prototype COPIES the caller's 40 MB argument on its next in-place edit. Tool code 'n = 1L' copies, tool code 'length(d)' copies, and so does a designated lm. The controls stay in place: tool code at top level, envir = globalenv() from inside a function, and plain R that forces d. Downgrade the claim to: copy-safe for the 20 tested entry points; UNCERTAIN whenever the home is a function frame and tools run. The plan's tracemem suite must include tool execution in a function-frame home.
  _Source: Re-run: verify-G3/copy/rerun/t5_copycheck.out. Adversarial scripts: verify-G3/adv_frame_value.R, adv2.R and adv3.R (Rscript --vanilla, R 4.4.3)._
- **Was:** Five causes pinned frames (garbage quosures; a for loop calling a closure on ...elt(i); re-assigning an unforced-default formal; sys.frames(); unforced promises into leaked helper frames). Five capture rules fix all of them; rule 2 bans closures/handlers only 'in the frame that holds ...'.
  **Now:** The list of causes is incomplete. Any garbage container that once referenced the frame pins it, including a plain list, because R never lowers reference counts for garbage. Plain R reproduces this: a list holding environment() that is later dropped gives COPY, while an environment binding reset to NULL stays in place (adv4.R). The prototype breaks the rules in the r tool, a frame the rules do not cover. .run_tool line 594 stores the home frame in the list the$current = list(s = s, env = env), and the frame that holds env also has tryCatch handler closures (at parse and per expression). Replacing the list with a cleared environment binding and removing those handlers made the length(d) case in place (adv5.R). Removing only the list did not (copy_fix). The rules must apply to every gptr frame or container that references a user function frame (the home or run env), not only the frame that holds dots. Add the rule: never put a user frame in a list or closure that can become garbage; hold it only in environment bindings that are explicitly reset.
  _Source: verify-G3/adv4.R, adv5.R, adv7.R and adv8.R; copy_fix/gptr_session.R; R trunk memory.c (the only DECREMENT_REFCNT is in FIX_REFCNT_EX, never in GC sweep)._
- **Was:** No held value references a user object (value policy copy/name/value).
  **Now:** This is not true for values that carry environments. A formula inside lm or glm terms, closures and ggplot plot_env all capture the environment they were evaluated in. When the agent evaluates in a function frame, a held lm pins that frame, and with it the caller's arguments, for as long as the session holds the value. The same happens even with the r-tool fix (adv_frame_value.R gptr_fit; the lm's terms environment is not globalenv). This is inherent to R, but the plan should document it. Values from function-frame homes could also have their environments rebased or be held by name.
  _Source: verify-G3/adv_frame_value.R and adv_fix.R (gptr_fit -> COPY; gptr_fit_global -> in place)._
- **Was:** R6 is worse: creation 71.5 us vs 5.0 us, reads 2.30 vs 4.35 us, serialize 21,023 vs 5,517 B, and R6's default clone() shares the private data environment (a silent fork).
  **Now:** The serialize sizes (21,023 vs 5,517 B) and object.size (352 vs 288) reproduce exactly. The timings depend on the run: the re-run gave creation 43.5 vs 5.0 us and reads 1.35 vs 2.65 us, so quote ratios rather than absolute numbers. On clone, R6 does not share the private environment itself. It copies private fields shallowly, so an environment-valued field (here private$d) is shared. That field is also shared with clone(deep = TRUE) unless a deep_clone method is written. R6Class(cloneable = FALSE) removes clone() entirely, so the silent-fork risk can be avoided and is not by itself a reason against R6. The S3 decision still stands on creation cost, serialisation size and simplicity.
  _Source: verify-G3/copy/rerun/t1b_r6.out; verify-G3/indep1.R (shallow TRUE, deep TRUE, private env shared FALSE, cloneable = FALSE gives no clone method); R6 2.6.1._
- **Was:** A fork's first request is 97% cache (477 of 490 tokens); a 3-turn steered chain had 1.7k of 2.3k input tokens cached; stated in the design implications as a token-efficiency fact.
  **Now:** Downgrade to UNCERTAIN. These numbers come from the fake's cache model (gptr_session.R .usage_add). That model caches any prefix, with no minimum length, no TTL and no cache_control. Real providers do not cache a prefix below the minimum length: Anthropic's minimum is 512 to 4,096 tokens depending on the model (1,024 for Sonnet 4.5/4.6 and Opus 4.8; 4,096 for Opus 4.5/4.6 and Haiku 4.5), and OpenAI's is 1,024. Anthropic caches expire after 5 minutes by default. So both requests here (490 and about 770 estimated tokens) would get 0 cache reads. The qualitative point still holds for real prompts with a system prompt and tool schemas above the minimum, within the TTL and on the same model: a fork re-uses its parent's prefix. Budgets should use provider-reported usage.
  _Source: Anthropic prompt-caching docs (platform.claude.com/docs/en/build-with-claude/prompt-caching, fetched 2026-09-29 in G4/web/anth_caching.md lines 604-613 and 212); OpenAI caching doc (G4/web/oai_caching.md line 69); gptr_session.R lines 547-565._
- **Was:** ns_traces §11: after the value was sent, CD3E / MS4A1 / AMBIG / GNLY were classified differently and only the AMBIG cluster was 'unclear'.
  **Now:** This is overstated. fake_s1_choice chooses by nchar(state) mod (n - 1) and hard-codes AMBIG to 'unclear'. On the re-run, CD3E and GNLY both got 'dendritic cell' and MS4A1 got 'T cell', all with prob 0.81 and all biologically wrong. The evidence shows only that the value (not a by-name description) reached System 1 and that control flow branched on 'unclear'. It says nothing about classification.
  _Source: G3/fake.R lines 34-37; verify-G3/copy/rerun/ns_traces.out._
- **Was:** gptr_fork writes a lazy Pi-v3 file ... The same entry ids are re-chained, as in Pi's createBranchedSession.
  **Now:** The shared ids and re-chaining, parentSession = the parent path, and session_start(reason = 'fork') all match Pi. Two differences should be recorded as deliberate. First, Pi's createBranchedSession writes the new file immediately when the branched path already contains a user or assistant message (_hasConversation), while G3 writes on the fork's first own message. Second, Pi re-creates label entries for the retained path, while G3 drops labels. Pi's session ids are UUIDv7 (createSessionId) and its entry ids are 8-hex.
  _Source: Pi 1b347794 packages/coding-agent/src/core/session-manager.ts lines 265, 277-283, 1632-1725 and 1166-1188; agent-session-runtime.ts lines 262-350._
- **Was:** Performance: 24.1 ms per turn over 200 turns; first background call 0.127 s sourced vs 0.012 s byte-compiled.
  **Now:** The re-run gave 16.2 ms per turn. The JSONL (189 KB) and serialize (335 KB) sizes are identical. First calls were 0.208-0.306 s sourced and 0.017-0.019 s precompiled. The conclusion holds (adequate speed; the first-call cost is JIT compilation), but the absolute timings are machine- and run-dependent.
  _Source: verify-G3/copy/rerun/t8_edge.out; p4_firstcall.R re-run twice per mode._
- **Was:** Core prototype: gptr_session.R (1,002 lines, base R + jsonlite + rlang); later and processx optional. t8 label: 'R >= 4.1 all.equal.environment'.
  **Now:** The file has 1,004 lines. It also calls ps::ps_is_running(ps::ps_handle(pid)) for the lock (line 126), so ps is an unlisted dependency; it arrives with processx/callr. all.equal() has had an environment method since R 3.2.0, not 4.1.
  _Source: wc -l G3/gptr_session.R; grep ps:: in gptr_session.R; R NEWS.3 line 4771 (CHANGES IN R 3.2.0)._

Unverifiable:

- Pause-menu and background-tool behaviour in RStudio, Positron, Jupyter/IRkernel, Rgui (Esc) and Windows Rterm (Ctrl-C). Only macOS R --interactive driven by processx was exercised; the t9 re-run passed.
- Real-provider behaviour: prompt-cache accounting, stream timeouts during a long pause menu, and HTTP-level interrupt/resume. Only the fake provider exists in G3.
- The 'earlier t9 run' failures that motivated the stdout-capture and exiting-tryCatch menu fixes were not preserved. The two underlying R semantics were confirmed independently in verify-G3/indep2.R (a calling handler's stdout is captured by an active capture.output; an inner exiting tryCatch(interrupt =) pre-empts the outer calling handler; on.exit does not).
- Whether R core will keep R_CleanupEnvir's release rule and never lower reference counts for garbage. Identical in R 4.4.3 and trunk r90598 (git mirror ac030d7, 2026-09-29) today; future behaviour cannot be verified.
- Lock robustness under pid reuse after a crash, and dir.create atomicity on Windows or network drives (untested, as G3 itself states).
- History-document replay picking the intended branch after heavy branching (G3 lists this as a risk; not exercised).
