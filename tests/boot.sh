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
# The image boots twice, with what the Supervisor grants from config.yaml with
# protection mode on and with it off. A key that only takes effect with
# protection mode off can break the boot for exactly the users who turn it off
# (host_pid does: s6-overlay refuses to run unless it is PID 1).
#
# Usage: tests/boot.sh [image]   (default: builds hetrixtools-agent:boot)
# BOOT_PLATFORM selects the image platform (default linux/amd64). CI sets it to
# the runner's native platform so each arch boots without emulation.
set -euo pipefail

IMAGE="${1:-}"
TIMEOUT="${BOOT_TIMEOUT:-60}"
PLATFORM="${BOOT_PLATFORM:-linux/amd64}"
CONFIG=hetrixtools-agent/config.yaml

if [ -z "$IMAGE" ]; then
  IMAGE=hetrixtools-agent:boot
  docker build --platform "$PLATFORM" -t "$IMAGE" hetrixtools-agent
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

# config.yaml booleans are written `key: true`; anything else counts as off.
cfg_true() { grep -qE "^$1: true( |#|$)" "$CONFIG"; }

# What the Supervisor grants regardless of protection mode.
protected=()
cfg_true host_network && protected+=(--network=host)
while read -r cap; do
  protected+=(--cap-add "$cap")
done < <(sed -nE '/^privileged:/,/^[^ -]/s/^ +- +"?([A-Z_]+)"?.*/\1/p' "$CONFIG")
# What it adds once the user turns protection mode off.
unprotected=("${protected[@]}")
cfg_true full_access && unprotected+=(--privileged)
cfg_true host_pid && unprotected+=(--pid=host)

fail=0
# Usage: boot <label> [docker run args...]
boot() {
  local label="$1"; shift
  echo "==== boot: ${label} ($*)"
  cid="$(docker run -d --platform "$PLATFORM" "$@" \
    --add-host supervisor:host-gateway \
    -e SUPERVISOR_API="http://supervisor:${PORT}" \
    -e SUPERVISOR_TOKEN=boot-test \
    "$IMAGE")"

  for _ in $(seq 1 "$TIMEOUT"); do
    docker logs "$cid" >"$log" 2>&1 || true
    grep -q "Starting HetrixTools agent loop" "$log" && break
    # A container that already exited (s6 refusing to start, say) will not
    # get any further; stop waiting.
    [ "$(docker inspect -f '{{.State.Running}}' "$cid")" = true ] || break
    sleep 1
  done
  docker logs "$cid" >"$log" 2>&1 || true
  cat "$log"
  echo "----"

  grep -q "service hetrixtools successfully started" "$log" \
    || { echo "FAIL (${label}): s6-rc never started the hetrixtools service (is it in the user bundle?)"; fail=1; }
  grep -q "dry_run enabled" "$log" \
    || { echo "FAIL (${label}): bashio never read the stub options (dry_run not seen)"; fail=1; }
  grep -q "Starting HetrixTools agent loop" "$log" \
    || { echo "FAIL (${label}): run script did not reach the agent loop within ${TIMEOUT}s"; fail=1; }
  # s6-overlay prints deprecations from rc.init. They are warnings today and
  # boot failures in the next major, so treat them as failures here.
  if grep -E "rc\.init: (warning|fatal)" "$log"; then
    echo "FAIL (${label}): s6-overlay init reported the line(s) above"
    fail=1
  fi
  if grep -E "\] ERROR: " "$log"; then
    echo "FAIL (${label}): bashio logged an error"
    fail=1
  fi

  docker rm -f "$cid" >/dev/null 2>&1 || true
  cid=""
}

boot "protection mode on" "${protected[@]}"
boot "protection mode off" "${unprotected[@]}"

[ "$fail" -eq 0 ] && echo "BOOT OK"
exit "$fail"
