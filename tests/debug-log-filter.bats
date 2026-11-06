#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  FILTER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/debug-log-filter.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345"
}

@test "shortens every occurrence of the SID, on every line" {
  run bash "$FILTER" "$SID" <<<"JSON: {\"SID\":\"$SID\"}
again $SID and $SID"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'JSON: {"SID":"abcdef…"}' ]
  [ "${lines[1]}" = 'again abcdef… and abcdef…' ]
}

@test "passes other lines through unchanged" {
  run bash "$FILTER" "$SID" <<<"PING_OUTPUT: 64 bytes from 1.1.1.1: icmp_seq=1 ttl=57"
  [ "$status" -eq 0 ]
  [ "$output" = "PING_OUTPUT: 64 bytes from 1.1.1.1: icmp_seq=1 ttl=57" ]
}

@test "refuses a malformed SID without printing its input" {
  # Anything but [A-Za-z0-9]{32} is unsafe as a sed pattern, and printing the
  # input unredacted would be the leak this filter exists to prevent.
  run -2 bash "$FILTER" "abc/def" <<<"secret line"
  [[ "$output" != *"secret line"* ]]
}

@test "replaces control characters other than tab, keeping the line" {
  # Probe output reaches debug.log from the network. An escape sequence would
  # reach the terminal of whoever reads the Log tab, and a carriage return
  # could overwrite the start of a line; each becomes a visible "?".
  run bash "$FILTER" "$SID" < <(printf 'a\033[31mb\rc\td\001e\177f\n')
  [ "$status" -eq 0 ]
  [ "$output" = $'a?[31mb?c\td?e?f' ]
}
