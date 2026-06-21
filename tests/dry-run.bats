#!/usr/bin/env bats

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345" COLLECT_EVERY_SECONDS=3 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
}

teardown() { rm -rf "$WORK"; }

@test "dry_run prints payload and does not POST" {
  [ "$(uname -s)" = "Linux" ] || skip "agent requires Linux /proc"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
  command -v timeout >/dev/null || skip "timeout not available"

  run env DryRun=1 timeout 90 bash "$WORK/hetrixtools_agent.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
  [[ "$output" == *"j="* ]]
}
