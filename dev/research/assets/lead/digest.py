"""Build dev/research/00-digest.md from every workflow journal of this session."""
import json, glob, os, re, sys
ROOT = "/Users/wanjun/.claude/projects/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/subagents/workflows"
OUT = "/Users/wanjun/Desktop/gptr/dev/research/00-digest.md"
research, verify = {}, {}
for j in sorted(glob.glob(os.path.join(ROOT, "*", "journal.jsonl")), key=os.path.getmtime):
    for line in open(j, encoding="utf-8"):
        try: e = json.loads(line)
        except Exception: continue
        if e.get("type") != "result": continue
        r = e.get("result")
        if not isinstance(r, dict) or "report_path" not in r: continue
        name = os.path.basename(r["report_path"])
        if "verdict" in r: verify[name] = r
        elif r.get("summary"): research[name] = r
names = sorted(set(research) | set(verify) | {os.path.basename(p) for p in glob.glob("/Users/wanjun/Desktop/gptr/dev/research/*.md")} - {"00-digest.md"})
out = ["# Research digest", "",
       "Generated from the structured results returned by each research and fact-check agent.",
       "One section per report. Read this first; open the full report only for the exact",
       "specifications and verified prototypes you need.", "",
       "| Report | Size | Fact-check verdict | Claims checked | Corrections |", "|---|---|---|---|---|"]
for n in names:
    p = "/Users/wanjun/Desktop/gptr/dev/research/" + n
    size = f"{os.path.getsize(p)//1024} KB" if os.path.exists(p) else "missing"
    v = verify.get(n)
    out.append(f"| [{n}]({n}) | {size} | {v['verdict'] if v else 'pending'} | {v.get('claims_checked','') if v else ''} | {len(v.get('corrections',[])) if v else ''} |")
for n in names:
    r, v = research.get(n), verify.get(n)
    out += ["", "---", "", f"## {n}", ""]
    if not r:
        out.append("_No structured summary (written by the lead designer or summary pending); read the report._")
    else:
        out += ["### Summary", "", r["summary"].strip(), "", "### Design implications", ""]
        out += [f"- {x}" for x in r.get("design_implications", [])]
        out += ["", "### Risks", ""] + [f"- {x}" for x in r.get("risks", [])]
        out += ["", "### Open questions", ""] + [f"- {x}" for x in r.get("open_questions", [])]
    if v:
        out += ["", f"### Fact-check: {v['verdict']} ({v.get('claims_checked','?')} claims checked)", ""]
        if v.get("notes"): out += [v["notes"].strip(), ""]
        if v.get("corrections"):
            out.append("Corrections applied to the report:"); out.append("")
            out += [f"- **Was:** {c['original_claim']} **Now:** {c['correction']} _(source: {c['source']})_" for c in v["corrections"]]
        if v.get("unverifiable"):
            out += ["", "Could not be verified:", ""] + [f"- {x}" for x in v["unverifiable"]]
open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"digest: {len(names)} reports, {len(research)} summaries, {len(verify)} verdicts, {os.path.getsize(OUT)//1024} KB")
