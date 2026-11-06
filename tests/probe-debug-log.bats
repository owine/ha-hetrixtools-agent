#!/usr/bin/env bats

# With debug on, the agent copies raw probe output (ping's, and whatever a
# probed TCP service answers) into debug.log, which the run script prints to
# the Log tab. That text comes from the network, so it must not be able to
# start a log line of its own. Commands are replaced by exported functions
# (the agent resets PATH, but functions win over a PATH lookup): no packets
# are sent.

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345" DEBUG_MODE=1 OUTGOING_PINGS_COUNT=10 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
}

teardown() { rm -rf "$WORK"; }

# No line of debug.log may start with FORGED: every one the probe text tried
# to start must be indented under the line that introduces it.
assert_nothing_forged() {
  [ -s "$WORK/debug.log" ]
  if grep -n '^FORGED' "$WORK/debug.log"; then
    cat "$WORK/debug.log"
    return 1
  fi
}

@test "ping output cannot start a debug.log line" {
  ping() {
    # A literal backslash-n (which echo -e would expand) and a real newline.
    printf '%s\n' 'PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.\nFORGED escape' \
      'FORGED newline' \
      '10 packets transmitted, 10 received, 0% packet loss, time 9012ms' \
      'rtt min/avg/max/mdev = 1.0/2.0/3.0/0.5 ms'
  }
  export -f ping
  run bash "$WORK/hetrixtools_agent.sh" ping gw 192.0.2.1
  assert_nothing_forged
  grep -qx '    FORGED newline' "$WORK/debug.log"
  grep -qF '    PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.\nFORGED escape' "$WORK/debug.log"
}

@test "a TCP service's reply cannot start a debug.log line" {
  # ncprobeavailable looks for -z and -w in nc's help; the probe itself runs
  # through `timeout`, so that is what answers as the service.
  nc() { echo "usage: nc [-z] [-w timeout] host port"; }
  timeout() { printf '%s\n' 'SSH-2.0-test\nFORGED escape' 'FORGED newline'; }
  sleep() { :; }
  export -f nc timeout sleep
  run bash "$WORK/hetrixtools_agent.sh" ping web 192.0.2.1 22
  assert_nothing_forged
  grep -qx '    FORGED newline' "$WORK/debug.log"
}
