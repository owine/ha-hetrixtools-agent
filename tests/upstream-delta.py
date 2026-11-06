#!/usr/bin/env python3
"""Check the vendored agent is upstream plus only the declared ha-app patches.

Usage:
  upstream-delta.py UPSTREAM VENDORED MANIFEST   check (exit 1 on any drift)
  upstream-delta.py --suggest UPSTREAM VENDORED  print a manifest to review

Every local change to the vendored hetrixtools_agent.sh sits in a block from
a `# >>> ha-app patch` line to a `# <<< ha-app patch <<<` line. The manifest
(hetrixtools-agent/upstream-agent.patches) has one line per block, in order:

  <upstream lines the block replaces> <first 16 hex of their sha256> <title>

The check walks both files in step: every vendored line outside a block must
be the next upstream line, and each block consumes exactly its declared
upstream span, whose hash must match. So an upstream line dropped, added or
changed anywhere, including next to or inside a replaced span, fails, and a
change in what a block replaces shows up in the manifest's diff.

--suggest derives the counts by matching the text after each block, for a
maintainer re-vendoring; review its output, since CI trusts the manifest.
"""
import hashlib
import re
import sys

OPEN = re.compile(rb"[ \t]*# >>> ha-app patch(?::[ \t]*(.*?))?[ \t]*(?:>>>)?$")
CLOSE = re.compile(rb"[ \t]*# <<< ha-app patch <<<$")


class Drift(Exception):
    pass


def read_lines(path):
    with open(path, "rb") as f:
        data = f.read()
    if b"\r" in data:
        raise Drift(f"{path}: contains a carriage return (CRLF line endings?)")
    if data and not data.endswith(b"\n"):
        raise Drift(f"{path}: does not end with a newline")
    return data.split(b"\n")[:-1]


def span_hash(lines):
    return hashlib.sha256(b"".join(line + b"\n" for line in lines)).hexdigest()[:16]


def blocks_of(vendored):
    """Return [(open_index, close_index, title)], rejecting bad nesting."""
    blocks, start = [], None
    for i, line in enumerate(vendored):
        if OPEN.match(line):
            if start is not None:
                raise Drift(f"vendored line {i + 1}: patch block opened inside another")
            start = i
        elif CLOSE.match(line):
            if start is None:
                raise Drift(f"vendored line {i + 1}: patch block closed but never opened")
            title = (OPEN.match(vendored[start]).group(1) or b"").decode(errors="replace")
            blocks.append((start, i, title))
            start = None
    if start is not None:
        raise Drift(f"vendored line {start + 1}: patch block never closed")
    return blocks


def segments(vendored, blocks):
    """Outside-block runs of vendored lines: before block 1, after each block."""
    edges = [-1] + [c for _, c, _ in blocks]
    starts = [o for o, _, _ in blocks] + [len(vendored)]
    return [vendored[e + 1:s] for e, s in zip(edges, starts)]


def check(upstream, vendored, manifest):
    blocks = blocks_of(vendored)
    entries = []
    for n, raw in enumerate(manifest, 1):
        if not raw.strip() or raw.startswith(b"#"):
            continue
        parts = raw.split(None, 2)
        if len(parts) < 2 or not parts[0].isdigit():
            raise Drift(f"manifest line {n}: expected '<count> <hash> <title>'")
        entries.append((int(parts[0]), parts[1].decode()))
    if len(entries) != len(blocks):
        raise Drift(f"{len(blocks)} patch blocks in the vendored agent, {len(entries)} in the manifest")

    u = 0
    segs = segments(vendored, blocks)
    for k, seg in enumerate(segs):
        for line in seg:
            if u >= len(upstream) or upstream[u] != line:
                raise Drift(f"outside the patch blocks, vendored text differs from upstream at "
                            f"upstream line {u + 1}: {line.decode(errors='replace')[:80]!r}")
            u += 1
        if k < len(blocks):
            count, want = entries[k]
            span = upstream[u:u + count]
            if len(span) != count or span_hash(span) != want:
                raise Drift(f"block {k + 1} ({blocks[k][2]}) at vendored line {blocks[k][0] + 1}: "
                            f"the {count} upstream lines from line {u + 1} do not hash to {want}. Either "
                            f"upstream changed what this patch replaces (re-review the patch, then "
                            f"update the manifest) or vendored lines next to the block were lost")
            u += count
    if u != len(upstream):
        raise Drift(f"upstream lines {u + 1}-{len(upstream)} are missing from the vendored agent")
    return blocks


def suggest(upstream, vendored):
    blocks = blocks_of(vendored)
    segs = segments(vendored, blocks)
    out, u = [], 0
    for k, seg in enumerate(segs):
        if upstream[u:u + len(seg)] != seg:
            raise Drift(f"cannot align the text before block {k + 1} with upstream line {u + 1}")
        u += len(seg)
        if k == len(blocks):
            break
        nxt = segs[k + 1]
        for c in range(len(upstream) - u + 1):
            if (not nxt and u + c == len(upstream)) or (nxt and upstream[u + c:u + c + len(nxt)] == nxt):
                break
        else:
            raise Drift(f"cannot find the text after block {k + 1} in upstream")
        out.append(f"{c} {span_hash(upstream[u:u + c])} {blocks[k][2]}")
        u += c
    return out


def main(argv):
    try:
        if len(argv) == 4 and argv[1] == "--suggest":
            print("# <upstream lines replaced> <sha256/16 of them> <block title>; see tests/upstream-delta.py")
            print("\n".join(suggest(read_lines(argv[2]), read_lines(argv[3]))))
            return 0
        if len(argv) == 4:
            blocks = check(read_lines(argv[1]), read_lines(argv[2]), read_lines(argv[3]))
            print(f"OK: upstream plus {len(blocks)} declared ha-app patch blocks")
            return 0
    except Drift as e:
        print(f"FAIL: {e}")
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
