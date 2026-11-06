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
  export PROBE_ARGS="$WORK/probe-args"
  nc() { echo "usage: nc host port"; }
  timeout() { printf '%s\n' "$@" > "$PROBE_ARGS"; }
  sleep() { :; }
  export -f nc timeout sleep
  run bash "$WORK/hetrixtools_agent.sh" ping web 192.0.2.1 22
  # -s 9 <seconds> bash -c <script> <$0> <target> <port>
  mapfile -t args < "$PROBE_ARGS"
  [ "${args[3]}" = bash ]
  [ "${args[4]}" = -c ]
  [[ "${args[5]}" != *192.0.2.1* ]]
  [[ "${args[5]}" == *'/dev/tcp/'* ]]
  [ "${args[7]}" = 192.0.2.1 ]
  [ "${args[8]}" = 22 ]
  # and the probe still reports the target
  [[ "$(cat "$WORK/ping.txt")" == web,192.0.2.1_22,0,* ]]
}
