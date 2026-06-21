#!/usr/bin/env bash
# Pure renderer: environment variables -> hetrixtools.cfg
# Usage: render-config.sh /path/to/hetrixtools.cfg
set -euo pipefail

CFG_PATH="${1:?cfg output path required}"

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
EOF
