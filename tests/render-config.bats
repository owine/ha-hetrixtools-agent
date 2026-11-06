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
  [[ "$output" == *'OutgoingPings=""'* ]]
  [[ "$output" == *'OutgoingPingsCount=20'* ]]
}

@test "renders ping targets separated by pipe, preserving commas within an entry" {
  # Entries are name,host[,port]; only the entry separator is a pipe.
  SID="abcdefghijklmnopqrstuvwxyz012345" \
  OUTGOING_PINGS="gw,192.168.1.1|dns,1.1.1.1|web,example.com,443" \
  OUTGOING_PINGS_COUNT=30 \
    bash "$RENDER" "$CFG"
  run cat "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'OutgoingPings="gw,192.168.1.1|dns,1.1.1.1|web,example.com,443"'* ]]
  [[ "$output" == *'OutgoingPingsCount=30'* ]]
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

# Each value becomes one `Key="value"` line of the cfg, so a newline in a
# value would start a cfg line of its own, such as SecuredConnection=0.
# ignored_disks is the one free-text option; the others are joined from
# lists with the line breaks already replaced.
@test "rejects a line break in a value rather than write a second cfg line" {
  for brk in $'\n' $'\r'; do
    rm -f "$CFG"
    run env SID="abcdefghijklmnopqrstuvwxyz012345" \
      IGNORED_DISKS="tmpfs${brk}SecuredConnection=0" bash "$RENDER" "$CFG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'ignored_disks'"* ]]
    [ ! -e "$CFG" ]
  done
}

@test "every value written to the cfg is checked for line breaks" {
  # A variable added to the template but not to the guard would be written
  # unchecked. Compare the two lists.
  written="$(sed -n '/^cat > "\$CFG_PATH" <<EOF$/,/^EOF$/p' "$RENDER" \
    | grep -oE '\$\{[A-Z_]+' | tr -d '${' | sort -u)"
  guarded="$(sed -n '/^for var in /,/; do$/p' "$RENDER" \
    | sed -e 's/^for var in //' -e 's/; do$//' | tr -s ' \t\\' '\n' | grep -E '^[A-Z_]+$' | sort -u)"
  [ -n "$written" ]
  [ "$written" = "$guarded" ]
}
