#!/usr/bin/env bats

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  # debug on as well, as DOCS.md asks for in bug reports: the SID must stay out
  # of debug.log too, since the run script copies that into the Log tab.
  SID="$SID" COLLECT_EVERY_SECONDS=3 DEBUG_MODE=1 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
}

teardown() { rm -rf "$WORK"; }

# One test, because each agent cycle takes about a minute.
@test "dry_run prints a readable payload with the SID shortened and does not POST" {
  [ "$(uname -s)" = "Linux" ] || skip "agent requires Linux /proc"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
  command -v timeout >/dev/null || skip "timeout not available"

  run env DryRun=1 timeout 90 bash "$WORK/hetrixtools_agent.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
  # The payload is the decoded JSON, not the gzip+base64 form that is POSTed:
  # that form hides nothing (it decodes in one line) and is unreadable.
  [[ "$output" == *'"SID":"abcdef…"'* ]]
  [[ "$output" != *"$SID"* ]]
  [ ! -e "$WORK/debug.log" ] || ! grep -qF "$SID" "$WORK/debug.log"
}
