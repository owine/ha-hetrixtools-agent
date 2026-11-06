#!/usr/bin/env bats

# The agent's `ping NAME TARGET` mode runs one ICMP probe and appends
# NAME,TARGET,LOSS,RTT_US; to ping.txt. ping is replaced by an exported
# function (the agent resets PATH, but functions win over a PATH lookup), so
# these tests send no packets and control exactly what the agent parses.

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345" bash "$RENDER" "$WORK/hetrixtools.cfg"
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || skip "agent requires bash >= 4"
}

teardown() { rm -rf "$WORK"; }

# Usage: probe_with_rtt_line "<rtt summary line ping prints>"
probe_with_rtt_line() {
  export PING_RTT_LINE="$1"
  ping() {
    printf '%s\n' "PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data." "" \
      "--- 192.0.2.1 ping statistics ---" \
      "20 packets transmitted, 20 received, 0% packet loss, time 19024ms" \
      "$PING_RTT_LINE"
  }
  export -f ping
  run bash "$WORK/hetrixtools_agent.sh" ping gw 192.0.2.1
}

@test "reports the average RTT in microseconds" {
  probe_with_rtt_line "rtt min/avg/max/mdev = 10.101/12.346/15.202/1.100 ms"
  [ "$(cat "$WORK/ping.txt")" = "gw,192.0.2.1,0,12346;" ]
}

@test "an RTT field that is not a number is read as data, never as awk code" {
  # Not something iputils prints; it stands in for any non-numeric text in
  # that field. Upstream pasted the field into the awk program, where this is
  # a syntax error and the RTT comes out empty. busybox awk (what the image
  # ships), gawk and mawk all print errors containing "awk: ". Read as data,
  # awk takes the leading numeric part, 12.3 ms.
  probe_with_rtt_line "rtt min/avg/max/mdev = 10.101/12.3)/15.202/1.100 ms"
  [[ "$output" != *"awk: "* ]]
  [ "$(cat "$WORK/ping.txt")" = "gw,192.0.2.1,0,12300;" ]
}
