#!/usr/bin/env bash
# Boot the image through its real s6-overlay init and check the layer smoke.sh
# deliberately bypasses: that s6-rc compiles and starts the hetrixtools service,
# and that bashio reads the app options and reaches the agent loop.
#
# This is the test that gates base-image bumps. A Renovate digest bump changes
# s6-overlay and bashio without touching any file in this repo, and only a real
# boot exercises them (s6-overlay 3.2.3.2 moved the user bundle, for example).
#
# bashio reads options from the Supervisor API, so a stub Supervisor is served
# from the runner host with python3 and reached via SUPERVISOR_API.
#
# Usage: tests/boot.sh [image]   (default: builds hetrixtools-agent:boot)
set -euo pipefail

IMAGE="${1:-}"
TIMEOUT="${BOOT_TIMEOUT:-60}"

if [ -z "$IMAGE" ]; then
  IMAGE=hetrixtools-agent:boot
  docker build --platform linux/amd64 -t "$IMAGE" hetrixtools-agent
fi

stub="$(mktemp -d)"
stub_log="$(mktemp)"
log="$(mktemp)"
cid=""
stub_pid=""
# shellcheck disable=SC2329  # invoked via the EXIT trap
cleanup() {
  [ -n "$cid" ] && docker rm -f "$cid" >/dev/null 2>&1 || true
  [ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null || true
  rm -rf "$stub" "$stub_log" "$log"
}
trap cleanup EXIT

# Every option the run script reads, with dry_run on so nothing is POSTed.
# The path is the one bashio::app.config requests:
# GET /addons/self/options/config.
mkdir -p "$stub/addons/self/options"
cat > "$stub/addons/self/options/config" <<'JSON'
{"result": "ok", "data": {
  "sid": "abcdefghijklmnopqrstuvwxyz012345",
  "collect_every_seconds": 3,
  "check_drive_health": false,
  "check_soft_raid": false,
  "check_reboot": false,
  "running_processes": false,
  "connection_ports": [],
  "check_services": [],
  "ignored_disks": "",
  "outgoing_pings": [],
  "outgoing_pings_count": 20,
  "dry_run": true,
  "debug": false
}}
JSON
# Port 0 lets the OS pick a free port. http.server prints its "Serving HTTP
# on ... port N" line only after binding, so waiting for that line both
# discovers the port and closes the race with the container's first request.
python3 -u -m http.server 0 --bind 0.0.0.0 --directory "$stub" >"$stub_log" 2>&1 &
stub_pid=$!
PORT=""
for _ in $(seq 1 50); do
  PORT="$(sed -nE 's/^Serving HTTP on .* port ([0-9]+) .*/\1/p' "$stub_log")"
  [ -n "$PORT" ] && break
  kill -0 "$stub_pid" 2>/dev/null || break
  sleep 0.2
done
if [ -z "$PORT" ] || ! curl -fsS "http://127.0.0.1:${PORT}/addons/self/options/config" | grep -q '"dry_run": true'; then
  cat "$stub_log"
  echo "FAIL: stub Supervisor did not come up"
  exit 1
fi

cid="$(docker run -d --platform linux/amd64 \
  --add-host supervisor:host-gateway \
  -e SUPERVISOR_API="http://supervisor:${PORT}" \
  -e SUPERVISOR_TOKEN=boot-test \
  "$IMAGE")"

for _ in $(seq 1 "$TIMEOUT"); do
  docker logs "$cid" >"$log" 2>&1 || true
  grep -q "Starting HetrixTools agent loop" "$log" && break
  sleep 1
done
cat "$log"
echo "----"

fail=0
grep -q "service hetrixtools successfully started" "$log" \
  || { echo "FAIL: s6-rc never started the hetrixtools service (is it in the user bundle?)"; fail=1; }
grep -q "dry_run enabled" "$log" \
  || { echo "FAIL: bashio never read the stub options (dry_run not seen)"; fail=1; }
grep -q "Starting HetrixTools agent loop" "$log" \
  || { echo "FAIL: run script did not reach the agent loop within ${TIMEOUT}s"; fail=1; }
# s6-overlay prints deprecations from rc.init. They are warnings today and
# boot failures in the next major, so treat them as failures here.
if grep -E "rc\.init: (warning|fatal)" "$log"; then
  echo "FAIL: s6-overlay init reported the line(s) above"
  fail=1
fi
if grep -E "\] ERROR: " "$log"; then
  echo "FAIL: bashio logged an error"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "BOOT OK"
exit "$fail"
