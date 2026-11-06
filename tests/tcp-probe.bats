#!/usr/bin/env bats

# The /dev/tcp and telnet TCP probes run a `bash -c` script. The target and
# port must reach it as arguments, never as part of the script text: they are
# regex-checked today, but the script should not depend on that.
# `timeout` (which runs the probe) is replaced by an exported function that
# records its arguments, and `nc` by one whose help lacks -z, so the agent
# picks /dev/tcp. No connection is made to the target.

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345" OUTGOING_PINGS_COUNT=10 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
}

teardown() { rm -rf "$WORK"; }

@test "the /dev/tcp probe passes target and port as arguments" {
  # The probe goes to 127.0.0.1:1, which refuses: bash's error then names the
  # /dev/tcp path the script really opened, so the inner script is exercised
  # too, not only its arguments.
  export PROBE_ARGS="$WORK/probe-args" PROBE_ERR="$WORK/probe-err"
  nc() { echo "usage: nc host port"; }
  timeout() { printf '%s\n' "$@" > "$PROBE_ARGS"; shift 3; "$@" 2>>"$PROBE_ERR"; }
  sleep() { :; }
  export -f nc timeout sleep
  run bash "$WORK/hetrixtools_agent.sh" ping lo 127.0.0.1 1
  # -s 9 <seconds> bash -c <script> <$0> <target> <port>
  mapfile -t args < "$PROBE_ARGS"
  [ "${args[3]}" = bash ]
  [ "${args[4]}" = -c ]
  [[ "${args[5]}" != *127.0.0.1* ]]
  [ "${args[7]}" = 127.0.0.1 ]
  [ "${args[8]}" = 1 ]
  grep -qF '/dev/tcp/127.0.0.1/1' "$PROBE_ERR"
  # and the probe reports the refused port as lost
  [[ "$(cat "$WORK/ping.txt")" == lo,127.0.0.1_1,100,* ]]
}
