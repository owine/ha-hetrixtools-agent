#!/usr/bin/env bash
# Build the amd64 image and verify the agent renders cfg + emits a payload in dry_run,
# WITHOUT depending on the HA supervisor (we invoke render + agent directly).
set -euo pipefail

# Build the amd64 slice of the multi-arch base pinned as the Dockerfile's
# BUILD_FROM default (no --build-arg override), so this exercises the real base.
# --platform linux/amd64 selects the amd64 manifest entry (also needed on Apple
# Silicon hosts).
docker build \
  --platform linux/amd64 \
  -t hetrixtools-agent:smoke \
  hetrixtools-agent

# --entrypoint bash bypasses the base image's s6-overlay init so we test the
# agent directly, without the supervised service trying (and failing) to reach
# a non-existent HA Supervisor and cluttering the output.
docker run --rm --platform linux/amd64 --entrypoint bash hetrixtools-agent:smoke -lc '
  set -e
  LIB=/usr/lib/hetrixtools
  export SID=abcdefghijklmnopqrstuvwxyz012345 COLLECT_EVERY_SECONDS=3
  bash "$LIB/render-config.sh" /tmp/hetrixtools.cfg
  cp "$LIB/hetrixtools_agent.sh" /tmp/hetrixtools_agent.sh
  cd /tmp
  DryRun=1 timeout 90 bash /tmp/hetrixtools_agent.sh | tee /tmp/out
  grep -q "j=" /tmp/out
'
echo "SMOKE OK"
