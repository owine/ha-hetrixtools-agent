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
  [[ "$output" == *'DEBUG=0'* ]]
  # Carries upstream's own four terms forward, since setting IgnoredDisks
  # replaces the agent's default rather than extending it.
  [[ "$output" == *'IgnoredDisks="tmpfs|aufs|squashfs|container_tmp|^overlay"'* ]]
}

@test "default disk filter is a valid extended regex" {
  # The agent silently disables filtering if this does not compile.
  SID="abcdefghijklmnopqrstuvwxyz012345" bash "$RENDER" "$CFG"
  filter="$(sed -n 's/^IgnoredDisks="\(.*\)"$/\1/p' "$CFG")"
  [ -n "$filter" ]
  run bash -c "printf '' | grep -E -- '$filter'"
  [ "$status" -ne 2 ]
}
@test "default disk filter drops the container overlay root but keeps real disks" {
  SID="abcdefghijklmnopqrstuvwxyz012345" bash "$RENDER" "$CFG"
  filter="$(sed -n 's/^IgnoredDisks="\(.*\)"$/\1/p' "$CFG")"
  cat > "$TMP/df.txt" <<'DF'
overlay overlay 100 50 50 50% /
tmpfs tmpfs 10 1 9 10% /dev/shm
/dev/sda1 ext4 900 100 800 11% /mnt/data
/dev/sdb1 ext4 900 100 800 11% /mnt/overlay-backup
DF
  run grep -v -E -- "$filter" "$TMP/df.txt"
  [[ "$output" != *"overlay overlay"* ]]
  [[ "$output" != *"/dev/shm"* ]]
  [[ "$output" == *"/mnt/data"* ]]
  # Anchoring keeps a real disk whose MOUNT PATH merely contains "overlay".
  [[ "$output" == *"/mnt/overlay-backup"* ]]
}

@test "maps booleans and lists" {
  SID="abcdefghijklmnopqrstuvwxyz012345" \
  COLLECT_EVERY_SECONDS=5 \
  CHECK_DRIVE_HEALTH=1 CHECK_SOFT_RAID=1 CHECK_REBOOT=0 RUNNING_PROCESSES=1 \
  CONNECTION_PORTS="80,443" CHECK_SERVICES="ssh,cron" \
  NETWORK_INTERFACES="end0,wlan0" \
  IGNORED_DISKS="tmpfs|myfs" DEBUG_MODE=1 \
    bash "$RENDER" "$CFG"
  run cat "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CheckDriveHealth=1'* ]]
  [[ "$output" == *'CheckSoftRAID=1'* ]]
  [[ "$output" == *'RunningProcesses=1'* ]]
  [[ "$output" == *'ConnectionPorts="80,443"'* ]]
  [[ "$output" == *'CheckServices="ssh,cron"'* ]]
  [[ "$output" == *'NetworkInterfaces="end0,wlan0"'* ]]
  [[ "$output" == *'DEBUG=1'* ]]
  [[ "$output" == *'IgnoredDisks="tmpfs|myfs"'* ]]
}

@test "fails when SID missing" {
  run bash "$RENDER" "$CFG"
  [ "$status" -ne 0 ]
}
