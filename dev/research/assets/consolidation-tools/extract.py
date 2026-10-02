import re, os, glob, json, sys
plan_dir = "/Users/wanjun/Desktop/gptr/dev/plan"
out = "blocks"; os.makedirs(out, exist_ok=True)
for f in glob.glob(out + "/*"): os.remove(f)
plans = sorted(glob.glob(plan_dir + "/P[0-2][0-9]-*.md"))
plans = [p for p in plans if int(os.path.basename(p)[1:3]) <= 25]
meta = []
fence_re = re.compile(r'^(\s*)(`{3,}|~{3,})(.*)$')
for p in plans:
    pid = os.path.basename(p)[:3]
    lines = open(p, encoding="utf-8").read().split("\n")
    stack = []  # (char, n, info, start, depth)
    cur = []
    i = 0
    nb = 0
    while i < len(lines):
        ln = lines[i]
        m = fence_re.match(ln)
        if m:
            fence = m.group(2); info = m.group(3).strip()
            ch, n = fence[0], len(fence)
            if stack and stack[-1][0] == ch and n >= stack[-1][1] and info == "":
                c, nn, inf, start, body = stack.pop()
                nb += 1
                lang = inf.split()[0].lower() if inf else ""
                depth = len(stack)
                meta.append(dict(plan=pid, start=start + 1, end=i + 1, lang=lang, depth=depth, n=len(body)))
                fn = "%s/%s_L%05d_%s_d%d.txt" % (out, pid, start + 1, lang or "plain", depth)
                open(fn, "w", encoding="utf-8").write("\n".join(body) + "\n")
                if stack:
                    stack[-1][4].extend(lines[start:i + 1])
                i += 1
                continue
            if not stack or (stack and n < stack[-1][1]) :
                # open new (nested only if outer fence is longer)
                if stack and not (n < stack[-1][1]):
                    pass
                stack.append([ch, n, info, i, []])
                i += 1
                continue
        if stack:
            stack[-1][4].append(ln)
        i += 1
    if stack:
        print("UNCLOSED", pid, [(s[2], s[3] + 1) for s in stack])
json.dump(meta, open("meta.json", "w"), indent=0)
import collections
print(collections.Counter((m["lang"], m["depth"]) for m in meta))
