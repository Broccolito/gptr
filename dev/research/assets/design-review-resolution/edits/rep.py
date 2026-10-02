import sys, json
def apply(path, pairs):
    s = open(path).read()
    errs = []
    for i, (old, new) in enumerate(pairs):
        n = s.count(old)
        if n != 1:
            errs.append((i, n, old[:90]))
            continue
        s = s.replace(old, new)
    if errs:
        for e in errs: print("FAIL", e)
        sys.exit(1)
    open(path, "w").write(s)
    print("ok", len(pairs))
