"""Write dev/research/G3-*.md and G5-*.md from the design journal's structured results plus the
verified prototype files the agents left in scratch (embedded verbatim so the repo is self-contained)."""
import json, os, glob
J = "/Users/wanjun/.claude/projects/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/subagents/workflows/wf_94cbad23-aab/journal.jsonl"
S = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work"
OUT = "/Users/wanjun/Desktop/gptr/dev/research"
GAPS = {"G3": ("G3-session-object-pipe-steering", "Session object and pipe steering (S-8)"),
        "G5": ("G5-polyglot-glue-helpers", "R as token-efficient polyglot glue")}
res, ver = {}, {}
for line in open(J, encoding="utf-8"):
    e = json.loads(line)
    if e.get("type") != "result" or not isinstance(e.get("result"), dict): continue
    r = e["result"]; lab = ""
    for k in GAPS:
        if k in json.dumps(r)[:600] or k in r.get("report_path", ""): lab = k
    if not lab: continue
    (ver if "verdict" in r else res)[lab] = r
TEXT_EXT = (".R", ".r", ".sh", ".txt", ".out", ".py", ".sql", ".Rmd", ".qmd", ".md", ".json", ".jsonl", ".toml", ".yaml")
for k, (slug, title) in GAPS.items():
    r, v = res.get(k), ver.get(k)
    if not r: print("no research result for", k); continue
    L = [f"# {k} — {title}", "",
         "> Materialised by the lead designer from the gap researcher's structured output and the",
         "> verified prototype files it left in scratch (the subagent could not write this file itself).",
         "> Code is embedded verbatim below so the repository is self-contained. Prototype code may use",
         "> `<-`; convert to the house style (`=`, `|>`) when copying into the package (S-9).", "",
         "## 1. Summary", "", r["summary"].strip(), "", "## 2. Key findings", ""]
    for f in r.get("key_findings", []):
        L += [f"- **[{f['confidence'].upper()}]** {f['claim']}", f"  - Evidence: {f['evidence']}"]
    L += ["", "## 3. Design implications", ""] + [f"- {x}" for x in r.get("design_implications", [])]
    L += ["", "## 4. Risks", ""] + [f"- {x}" for x in r.get("risks", [])]
    L += ["", "## 5. Open questions", ""] + [f"- {x}" for x in r.get("open_questions", [])]
    d = os.path.join(S, k)
    files = []
    for p in sorted(glob.glob(os.path.join(d, "**", "*"), recursive=True)):
        rel = os.path.relpath(p, d)
        if os.path.isdir(p) or any(part.startswith(("lib", "rlib", ".")) for part in rel.split(os.sep)[:-1]): continue
        if not p.endswith(TEXT_EXT) or os.path.getsize(p) > 60000: continue
        files.append((rel, p))
    L += ["", f"## 6. Prototype files ({len(files)} files from `scratchpad/work/{k}/`)", ""]
    for rel, p in files:
        body = open(p, encoding="utf-8", errors="replace").read().rstrip("\n")
        lang = "r" if rel.endswith((".R", ".r")) else ("sh" if rel.endswith(".sh") else "text")
        L += [f"### `{rel}`", "", f"````{lang}", body, "````", ""]
    if v:
        L += ["## Verification log", "", f"Verdict: **{v['verdict']}** ({v['claims_checked']} claims checked).", "", v["notes"].strip(), ""]
        if v.get("corrections"):
            L += ["Corrections (apply these over the summary above):", ""]
            L += [f"- **Was:** {c['original_claim']}\n  **Now:** {c['correction']}\n  _Source: {c['source']}_" for c in v["corrections"]]
        if v.get("unverifiable"):
            L += ["", "Unverifiable:", ""] + [f"- {x}" for x in v["unverifiable"]]
    path = os.path.join(OUT, slug + ".md")
    open(path, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(path, os.path.getsize(path) // 1024, "KB,", len(files), "files embedded, verdict:", v["verdict"] if v else "none")
