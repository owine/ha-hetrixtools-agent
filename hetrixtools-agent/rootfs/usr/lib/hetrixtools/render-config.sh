#!/usr/bin/env bash
# Pure renderer: environment variables -> hetrixtools.cfg
# Usage: render-config.sh /path/to/hetrixtools.cfg
set -euo pipefail

CFG_PATH="${1:?cfg output path required}"

# Disk types to keep out of the report. Setting IgnoredDisks REPLACES the
# agent's own default rather than extending it, so the upstream four terms are
# carried forward here verbatim; `^overlay` is ours. Home Assistant runs add-ons
# under Docker's overlay2 storage driver, so without it the container's own root
# overlay is reported as if it were a host disk. It is anchored because the
# agent greps whole `df` lines, and an unanchored `overlay` would also swallow a
# real disk mounted at a path containing that word.
DEFAULT_IGNORED_DISKS='tmpfs|aufs|squashfs|container_tmp|^overlay'

if [ -z "${SID:-}" ]; then
	echo "render-config: SID is required" >&2
	exit 1
fi

cat > "$CFG_PATH" <<EOF
SID="${SID}"
CollectEveryXSeconds=${COLLECT_EVERY_SECONDS:-3}
CheckServices="${CHECK_SERVICES:-}"
CheckSoftRAID=${CHECK_SOFT_RAID:-0}
CheckDriveHealth=${CHECK_DRIVE_HEALTH:-0}
CheckReboot=${CHECK_REBOOT:-0}
RunningProcesses=${RUNNING_PROCESSES:-0}
ConnectionPorts="${CONNECTION_PORTS:-}"
NetworkInterfaces="${NETWORK_INTERFACES:-}"
IgnoredDisks="${IGNORED_DISKS:-$DEFAULT_IGNORED_DISKS}"
DEBUG=${DEBUG_MODE:-0}
EOF
