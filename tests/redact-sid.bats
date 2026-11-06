#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REDACT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/redact-sid.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345"
}

@test "shortens every occurrence of the SID, on every line" {
  run bash "$REDACT" "$SID" <<<"JSON: {\"SID\":\"$SID\"}
again $SID and $SID"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'JSON: {"SID":"abcdef…"}' ]
  [ "${lines[1]}" = 'again abcdef… and abcdef…' ]
}

@test "passes other lines through unchanged" {
  run bash "$REDACT" "$SID" <<<"PING_OUTPUT: 64 bytes from 1.1.1.1: icmp_seq=1 ttl=57"
  [ "$status" -eq 0 ]
  [ "$output" = "PING_OUTPUT: 64 bytes from 1.1.1.1: icmp_seq=1 ttl=57" ]
}

@test "refuses a malformed SID without printing its input" {
  # Anything but [A-Za-z0-9]{32} is unsafe as a sed pattern, and printing the
  # input unredacted would be the leak this filter exists to prevent.
  run -2 bash "$REDACT" "abc/def" <<<"secret line"
  [[ "$output" != *"secret line"* ]]
}
