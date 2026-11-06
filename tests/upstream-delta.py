#!/usr/bin/env python3
"""Check the vendored agent differs from upstream only inside ha-app patches.

Usage: upstream-delta.py UPSTREAM_AGENT VENDORED_AGENT

Every local change to the vendored hetrixtools_agent.sh must sit between a
`# >>> ha-app patch` line and a `# <<< ha-app patch <<<` line, so a re-vendor
can find and re-apply them. This lists every difference from the upstream
script and exits 1 if any lies outside such a block. CI runs it against the
upstream release named in hetrixtools-agent/upstream-agent.version.
"""
import difflib
import re
import sys

OPEN = re.compile(r"\s*# >>> ha-app patch")
CLOSE = re.compile(r"\s*# <<< ha-app patch <<<")


def main(upstream_path, vendored_path):
    with open(upstream_path) as f:
        upstream = f.read().splitlines()
    with open(vendored_path) as f:
        vendored = f.read().splitlines()

    inside, depth, blocks = [], 0, 0
    for line in vendored:
        if OPEN.match(line):
            depth += 1
            blocks += 1
        inside.append(depth > 0)
        if CLOSE.match(line):
            depth -= 1
    if depth != 0:
        print(f"unbalanced ha-app patch markers (depth {depth} at end of file)")
        return 1

    outside = 0
    matcher = difflib.SequenceMatcher(None, upstream, vendored, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if j2 > j1:
            ok = all(inside[j1:j2])
        else:  # upstream lines removed: the gap must be at a block edge
            ok = (j1 < len(vendored) and inside[j1]) or (j1 > 0 and inside[j1 - 1])
        outside += not ok
        print(f"{'ok ' if ok else 'BAD'} {tag:7} upstream {i1 + 1}-{i2} vendored {j1 + 1}-{j2}")
    print(f"{blocks} ha-app patch blocks; {outside} difference(s) outside them")
    return 1 if outside else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
