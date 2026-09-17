#!/usr/bin/env bats

setup() {
  DETECT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/detect-interfaces.sh"
  TMP="$(mktemp -d)"
  # A representative `ip a` from an HA OS host running Docker: one real NIC
  # (end0), the Supervisor bridge, Docker's default and user-defined bridges,
  # and the ephemeral veth pairs that caused the log spam.
  cat > "$TMP/ip-a.txt" <<'FIXTURE'
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether dc:a6:32:11:22:33 brd ff:ff:ff:ff:ff:ff
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:aa:bb:cc:dd brd ff:ff:ff:ff:ff:ff
4: hassio: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:11:22:33:44 brd ff:ff:ff:ff:ff:ff
5: br-9f3a1c2e4b5d: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:55:66:77:88 brd ff:ff:ff:ff:ff:ff
7: veth1a2b3c4@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master hassio state UP group default
    link/ether 7a:11:22:33:44:55 brd ff:ff:ff:ff:ff:ff
9: vethdeadbee@if8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master docker0 state UP group default
    link/ether 7a:aa:bb:cc:dd:ee brd ff:ff:ff:ff:ff:ff
FIXTURE
}

teardown() { rm -rf "$TMP"; }

@test "keeps the real NIC and drops container plumbing" {
  run bash -c "bash '$DETECT' < '$TMP/ip-a.txt'"
  [ "$status" -eq 0 ]
  [ "$output" = "end0" ]
}

@test "drops interfaces that are down and loopback" {
  # docker0 is state DOWN and lo lacks BROADCAST; neither may appear.
  run bash -c "bash '$DETECT' < '$TMP/ip-a.txt'"
  [[ "$output" != *"docker0"* ]]
  [[ "$output" != *"lo"* ]]
}

@test "emits multiple NICs comma-separated with no trailing comma" {
  cat >> "$TMP/ip-a.txt" <<'EXTRA'
11: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
EXTRA
  run bash -c "bash '$DETECT' < '$TMP/ip-a.txt'"
  [ "$status" -eq 0 ]
  [ "$output" = "end0,wlan0" ]
}

@test "keeps a user's own bridge (br0), which is not Docker's br-<hex>" {
  cat >> "$TMP/ip-a.txt" <<'EXTRA'
12: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether aa:11:bb:22:cc:33 brd ff:ff:ff:ff:ff:ff
EXTRA
  run bash -c "bash '$DETECT' < '$TMP/ip-a.txt'"
  [ "$output" = "end0,br0" ]
}

@test "exits cleanly with empty output when nothing matches" {
  # grep exits 1 on no match; the filter must not abort on that.
  run bash -c "printf '' | bash '$DETECT'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
