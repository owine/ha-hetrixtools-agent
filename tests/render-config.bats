#!/usr/bin/env bats

setup() {
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  TMP="$(mktemp -d)"
  CFG="$TMP/hetrixtools.cfg"
}

teardown() { rm -rf "$TMP"; }

@test "writes SID and applies defaults when only SID is set" {
  # Set ONLY SID so the script's :- fallbacks are actually exercised.
  SID="abcdefghijklmnopqrstuvwxyz012345" bash "$RENDER" "$CFG"
  run cat "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SID="abcdefghijklmnopqrstuvwxyz012345"'* ]]
  [[ "$output" == *'CollectEveryXSeconds=3'* ]]
  [[ "$output" == *'CheckDriveHealth=0'* ]]
  [[ "$output" == *'ConnectionPorts=""'* ]]
  # Empty is meaningful: the agent reads it as "auto-detect interfaces".
  [[ "$output" == *'NetworkInterfaces=""'* ]]
}

@test "maps booleans and lists" {
  SID="abcdefghijklmnopqrstuvwxyz012345" \
  COLLECT_EVERY_SECONDS=5 \
  CHECK_DRIVE_HEALTH=1 CHECK_SOFT_RAID=1 CHECK_REBOOT=0 RUNNING_PROCESSES=1 \
  CONNECTION_PORTS="80,443" CHECK_SERVICES="ssh,cron" \
  NETWORK_INTERFACES="end0,wlan0" \
    bash "$RENDER" "$CFG"
  run cat "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CheckDriveHealth=1'* ]]
  [[ "$output" == *'CheckSoftRAID=1'* ]]
  [[ "$output" == *'RunningProcesses=1'* ]]
  [[ "$output" == *'ConnectionPorts="80,443"'* ]]
  [[ "$output" == *'CheckServices="ssh,cron"'* ]]
  [[ "$output" == *'NetworkInterfaces="end0,wlan0"'* ]]
}

@test "fails when SID missing" {
  run bash "$RENDER" "$CFG"
  [ "$status" -ne 0 ]
}
