#!/usr/bin/env python3
"""Mechanical part of the D-135 rename: gptr() -> peter(), gptr$ -> peter$, gptr::gptr -> gptr::peter.

Usage: python3 rename.py <file>...   (rewrites in place, byte-preserving: CRLF, BOM and non-ASCII kept;
prints per-file counts). Lines that already contain "peter" (the D-135 notes) are left alone.
Kept by design (never matched): the package name and gptr:: qualifiers, gptr_* names, gptr.* options,
.gptr/, GPTR_*, gptr_error_* classes, S3 classes, `function(gptr)` extension factories and their API
members (gptr$register*, $on, $state, $require, $has, $name, $dir), stored entry fields
(e$gptr$..., [["gptr"]], `gptr$turn`, `gptr$reason`, `gptr$blocks`), markers `# >>> gptr:<id>`,
`gptr-<id>` chunk labels, `<gptr>` srcfile, `library(gptr)`.
Everything else that names the callable is in the manual list of inventory.md."""
import re, sys
KEEP = r'(?:register\w*|on|state|require|has|name|dir|turn|reason|blocks)\b'
LB = r'(?<![\w.$/\-\[])'          # not part of another identifier, path, field access or e$gptr
RULES = [
  ('qual',  re.compile(r'(?<=gptr::)gptr(?!\w)|(?<=gptr:::)gptr(?!\w)'), 'peter'),
  ('call',  re.compile(LB + r'gptr(?=\()'), 'peter'),
  ('ns',    re.compile(LB + r'gptr(?=\$(?!' + KEEP + r'))'), 'peter'),
  ('ns2',   re.compile(LB + r'gptr(?=\[\[)'), 'peter'),
  ('regex', re.compile(LB + r'gptr(?=\\\\[($])'), 'peter'),       # "gptr\\(" and "gptr\\$" in regex strings
  ('quote', re.compile(r'quote\(gptr\)'), 'quote(peter)'),
  ('def',   re.compile(r'^(\s*)gptr = (?=(?:structure\()?function\()', re.M), r'\1peter = '),
]
tot = {}
for p in sys.argv[1:]:
    try:
        raw = open(p, 'rb').read(); t = raw.decode('utf-8')
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
        continue
    n = dict.fromkeys([r[0] for r in RULES], 0)
    out = []
    for line in t.splitlines(keepends=True):
        if 'peter' not in line:
            for name, rx, rep in RULES:
                line, k = rx.subn(rep, line); n[name] += k
        out.append(line)
    if sum(n.values()):
        open(p, 'wb').write(''.join(out).encode('utf-8'))
        print(p, {k: v for k, v in n.items() if v})
        for k, v in n.items(): tot[k] = tot.get(k, 0) + v
print('TOTAL', tot, sum(tot.values()), file=sys.stderr)
