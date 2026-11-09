#!/usr/bin/env bats

# DOCS.md, which HA shows in the app store, names the vendored agent's version
# in prose. Nothing else ties that prose to upstream-agent.version, so a
# re-vendor left it saying v2.4.1 after the agent moved to 2.4.2, in two
# places. Every vX.Y.Z in DOCS.md is taken to be the agent's version; a
# mention of anything else would need this test to tell the two apart.

setup() {
  DOCS="hetrixtools-agent/DOCS.md"
  version="$(cat hetrixtools-agent/upstream-agent.version)"
}

@test "every version DOCS.md names is the vendored agent's" {
  run grep -noE 'v[0-9]+\.[0-9]+\.[0-9]+' "$DOCS"
  # At least one, so a rewording that drops the version cannot pass vacuously.
  [ "$status" -eq 0 ]
  stale="$(printf '%s\n' "$output" | grep -vx "[0-9]*:v${version//./\\.}" || true)"
  if [ -n "$stale" ]; then
    echo "DOCS.md names a version other than upstream-agent.version (${version}):"
    echo "$stale"
    false
  fi
}
