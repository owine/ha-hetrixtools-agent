#!/usr/bin/env bats

# Renovate tracks the vendored agent through a regex custom manager on
# hetrixtools-agent/upstream-agent.version. It compiles each matchString with
# only the `g` flag, so `$` means end of file. A pattern that cannot match
# the real file means the dependency is never detected and no update is ever
# proposed, with no error anywhere, which is what happened before this test.

setup() {
  command -v node >/dev/null || skip "node not available"
}

@test "the upstream agent matchString extracts the version from the real file" {
  run node -e '
    const c = require("./renovate.json");
    const m = c.customManagers.find(x => x.depNameTemplate === "hetrixtools/agent");
    const s = require("fs").readFileSync("hetrixtools-agent/upstream-agent.version", "utf8");
    const got = m.matchStrings.flatMap(p => [...s.matchAll(new RegExp(p, "g"))])
      .map(x => x.groups.currentValue);
    console.log(JSON.stringify(got));
    process.exit(got.length === 1 && got[0] === s.trim() ? 0 : 1);'
  [ "$status" -eq 0 ]
}
