#!/usr/bin/env bats

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  # debug on, as DOCS.md asks for in bug reports.
  SID="$SID" COLLECT_EVERY_SECONDS=3 DEBUG_MODE=1 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
}

teardown() { rm -rf "$WORK"; }

requires_agent_host() {
  [ "$(uname -s)" = "Linux" ] || skip "agent requires Linux /proc"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
  command -v timeout >/dev/null || skip "timeout not available"
}

# Each agent cycle takes about a minute, so each test runs the agent once.

@test "dry_run prints a readable payload with the SID shortened and does not POST" {
  requires_agent_host

  run env DryRun=1 timeout 90 bash "$WORK/hetrixtools_agent.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
  # The decoded JSON, not the gzip+base64 form that is POSTed: that form hides
  # nothing (it decodes in one line) and is unreadable.
  [[ "$output" == *'"SID":"abcdef…"'* ]]
  [[ "$output" != *"$SID"* ]]
}

@test "debug writes the payload JSON to debug.log with the SID shortened" {
  requires_agent_host

  # Without DryRun the agent POSTs, so replace wget. The agent resets PATH, but
  # an exported function still wins over a PATH lookup. The dead proxy is a
  # backstop: if the stub were ever bypassed, the real wget fails to connect
  # instead of reaching HetrixTools.
  export WGET_CALLS="$WORK/wget-calls"
  wget() { echo "stub wget $*" >> "$WGET_CALLS"; }
  export -f wget

  run env https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
    timeout 90 bash "$WORK/hetrixtools_agent.sh"
  [ "$status" -eq 0 ]
  # The debug branch ran, and its POST went to the stub.
  grep -q -- "--post-file=" "$WGET_CALLS"

  log="$(cat "$WORK/debug.log")"
  [[ "$log" == *'"SID":"abcdef…"'* ]]
  [[ "$log" != *"$SID"* ]]
}
