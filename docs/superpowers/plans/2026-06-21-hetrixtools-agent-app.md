# HetrixTools Agent — Home Assistant App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a publishable Home Assistant **app** that runs a vendored HetrixTools monitoring agent in a privileged container so it reports the real HA OS host to HetrixTools.

**Architecture:** A single HA app (modern 2026 conventions: `config.yaml`, no `build.yaml`, s6-overlay v3, GHCR-published images). A `bashio` s6 service reads app options, renders `hetrixtools.cfg`, and loops the vendored agent (one ~60s collect-then-POST cycle per invocation, crash-loop-guarded). Host visibility comes from `full_access`/`host_pid`/`host_network`/`udev`. The only patch to the vendored agent is a `dry_run` guard around its `wget` POST.

**Tech Stack:** Bash, `bashio`, s6-overlay v3, Docker (HA Alpine base), `bats-core` (tests), shellcheck/hadolint/yamllint, GitHub Actions (`home-assistant/builder`), release-please, renovate. Pinned upstream agent: **v2.4.1** (`ffd9af2037c6bf24fd671e0ce45ff34a6c7cfa91`).

**Reference spec:** `docs/superpowers/specs/2026-06-21-hetrixtools-agent-app-design.md`

---

## File Structure

```
ha-hetrixtools-agent/
├── repository.yaml                                  # app store metadata
├── hetrixtools-agent/
│   ├── config.yaml                                  # manifest: slug/arch/image/options/schema/privileges
│   ├── Dockerfile                                   # ARG BUILD_FROM + deps + copy rootfs/agent + LABELs
│   ├── CHANGELOG.md                                 # release-please managed (seed)
│   ├── DOCS.md                                       # user docs (Apps panel "Documentation" tab)
│   ├── README.md
│   ├── icon.png / logo.png                          # branding (placeholder until real art)
│   ├── upstream-agent.version                       # pinned upstream marker (renovate-tracked)
│   └── rootfs/
│       ├── usr/lib/hetrixtools/
│       │   ├── hetrixtools_agent.sh                 # VENDORED v2.4.1 + dry_run guard
│       │   └── render-config.sh                     # PURE: env → hetrixtools.cfg (unit-tested)
│       └── etc/s6-overlay/s6-rc.d/
│           ├── hetrixtools/
│           │   ├── type                             # "longrun"
│           │   └── run                              # bashio: options → env → render → loop
│           └── user/contents.d/
│               └── hetrixtools                      # empty file: registers the service
├── tests/
│   ├── render-config.bats                           # unit tests for render-config.sh
│   └── dry-run.bats                                 # agent dry_run emits parseable payload
├── .github/workflows/
│   ├── lint.yaml                                    # shellcheck + hadolint + yamllint + bats
│   └── build.yaml                                   # home-assistant/builder → GHCR
├── .shellcheckrc / .hadolint.yaml / .yamllint
├── release-please-config.json / .release-please-manifest.json
├── renovate.json
└── docs/superpowers/...                             # spec + this plan
```

**Decomposition rationale:** `render-config.sh` is a pure function (env vars in → cfg file out) so it is unit-testable with bats in isolation, separate from the s6 `run` orchestration script which needs the supervisor/`bashio`. The vendored agent stays untouched except one guarded POST. Files that change together (rootfs) live together.

---

## Task 1: Repo scaffolding & lint configs

**Files:**
- Create: `.gitignore`, `.shellcheckrc`, `.hadolint.yaml`, `.yamllint`
- Create: `hetrixtools-agent/upstream-agent.version`

- [ ] **Step 1: Create lint configs**

`.shellcheckrc`:
```
external-sources=true
disable=SC1091
```

`.hadolint.yaml`:
```yaml
ignored:
  - DL3008  # apk versions float; renovate handles base image pinning
trustedRegistries:
  - ghcr.io
  - docker.io
```

`.yamllint`:
```yaml
extends: default
rules:
  line-length:
    max: 120
  document-start: disable
  comments:
    min-spaces-from-content: 1
```

`.gitignore`:
```
*.log
.DS_Store
```

`hetrixtools-agent/upstream-agent.version`:
```
2.4.1
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore .shellcheckrc .hadolint.yaml .yamllint hetrixtools-agent/upstream-agent.version
git commit -m "chore: add lint configs and upstream agent version pin"
```

---

## Task 2: Vendor the HetrixTools agent (pinned v2.4.1) with dry_run guard

**Files:**
- Create: `hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh`

- [ ] **Step 1: Fetch the pinned upstream agent**

Run:
```bash
mkdir -p hetrixtools-agent/rootfs/usr/lib/hetrixtools
curl -fsSL \
  https://raw.githubusercontent.com/hetrixtools/agent/2.4.1/hetrixtools_agent.sh \
  -o hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
chmod +x hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
```
Expected: file exists, begins with `#!/bin/bash`, contains `Version="2.4.1"`.

- [ ] **Step 2: Verify the integration points before patching**

Run:
```bash
grep -n 'sm.hetrixtools.net/v2' hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
grep -n 'load_config' hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
grep -n 'hetrixtools_update' hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
```
Expected: the `wget … https://sm.hetrixtools.net/v2/` lines exist (two of them, inside the `DEBUG` if/else — see Step 3); `load_config "$ScriptPath"/hetrixtools.cfg` exists; **no** `hetrixtools_update` reference. Conclusion: **v2.4.1 has no self-update or scheduler code in this file — there is nothing to strip.** The only change we make is the Step 3 `dry_run` guard.

> Also note for later tasks: the agent does **not** validate that `SID` is non-empty — it will happily build a payload with an empty `SID` and only `exit 1` if the cfg file is missing entirely. Real SID validation is therefore done by the s6 run script (Task 5), not the agent.

- [ ] **Step 3: Add the `dry_run` guard around the POST block**

> IMPORTANT: in v2.4.1 the POST is **not** a single line. It lives inside a `DEBUG` if/else with **two** `wget` calls (a verbose debug variant and the quiet variant), immediately after the line that writes the payload: `echo "j=$jsoncomp" > "$ScriptPath"/hetrixtools_agent.log`. You must wrap the **whole `if [ "$DEBUG" -eq 1 ] … fi` block**, not one `wget` line. `DEBUG` is the agent's own cfg flag and is unrelated to our `dry_run` (render-config.sh never emits `DEBUG`, so it defaults to 0).

The exact upstream block to wrap is:
```bash
if [ "$DEBUG" -eq 1 ]
then
	echo -e "$ScriptStartTime-$(date +%T]) JSON:\n$json" >> "$ScriptPath"/debug.log
	# Post data
	echo -e "$ScriptStartTime-$(date +%T]) Posting data" >> "$ScriptPath"/debug.log
	wget -v --debug --retry-connrefused --waitretry=1 -t 3 -T 15 -O- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &>> "$ScriptPath"/debug.log
	echo -e "$ScriptStartTime-$(date +%T]) Data posted" >> "$ScriptPath"/debug.log
else
	# Post data
	wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &> /dev/null
fi
```

Replace it with the same block guarded by an outer `dry_run` short-circuit and patch markers (the `j=`-prefixed payload is already on disk at `$ScriptPath/hetrixtools_agent.log`, so dry_run just prints it):
```bash
# >>> ha-app patch: dry_run guard (re-apply after upstream bump) >>>
if [ "${DryRun:-0}" = "1" ]; then
	echo "[hetrixtools][dry_run] would POST payload (no network call):"
	cat "$ScriptPath/hetrixtools_agent.log"
elif [ "$DEBUG" -eq 1 ]
then
	echo -e "$ScriptStartTime-$(date +%T]) JSON:\n$json" >> "$ScriptPath"/debug.log
	# Post data
	echo -e "$ScriptStartTime-$(date +%T]) Posting data" >> "$ScriptPath"/debug.log
	wget -v --debug --retry-connrefused --waitretry=1 -t 3 -T 15 -O- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &>> "$ScriptPath"/debug.log
	echo -e "$ScriptStartTime-$(date +%T]) Data posted" >> "$ScriptPath"/debug.log
else
	# Post data
	wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &> /dev/null
fi
# <<< ha-app patch <<<
```
This guarantees neither POST branch can fire under `dry_run`, and the printed line literally starts with `j=` (satisfying the Task 4 assertion).

- [ ] **Step 4: Lint the vendored script**

Run: `shellcheck -x hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh || true`
Expected: no errors introduced by our patch (upstream may carry its own advisories; do not rewrite upstream — only ensure the patch block is clean). If upstream advisories are noisy, scope a `# shellcheck disable` to the vendored file header with a comment that it is third-party.

- [ ] **Step 5: Commit**

```bash
git add hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh
git commit -m "feat: vendor HetrixTools agent v2.4.1 with dry_run guard"
```

---

## Task 3: `render-config.sh` — pure cfg renderer (TDD)

**Files:**
- Create: `hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh`
- Test: `tests/render-config.bats`

- [ ] **Step 1: Write the failing test**

`tests/render-config.bats`:
```bash
#!/usr/bin/env bats

setup() {
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  TMP="$(mktemp -d)"
  CFG="$TMP/hetrixtools.cfg"
}

teardown() { rm -rf "$TMP"; }

@test "writes SID and defaults" {
  SID="abcdefghijklmnopqrstuvwxyz012345" \
  COLLECT_EVERY_SECONDS=3 \
  CHECK_DRIVE_HEALTH=0 CHECK_SOFT_RAID=0 CHECK_REBOOT=0 RUNNING_PROCESSES=0 \
  CONNECTION_PORTS="" CHECK_SERVICES="" \
    bash "$RENDER" "$CFG"
  run cat "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SID="abcdefghijklmnopqrstuvwxyz012345"'* ]]
  [[ "$output" == *'CollectEveryXSeconds=3'* ]]
}

@test "maps booleans and lists" {
  SID="abcdefghijklmnopqrstuvwxyz012345" \
  COLLECT_EVERY_SECONDS=5 \
  CHECK_DRIVE_HEALTH=1 CHECK_SOFT_RAID=1 CHECK_REBOOT=0 RUNNING_PROCESSES=1 \
  CONNECTION_PORTS="80,443" CHECK_SERVICES="ssh,cron" \
    bash "$RENDER" "$CFG"
  run cat "$CFG"
  [[ "$output" == *'CheckDriveHealth=1'* ]]
  [[ "$output" == *'CheckSoftRAID=1'* ]]
  [[ "$output" == *'RunningProcesses=1'* ]]
  [[ "$output" == *'ConnectionPorts="80,443"'* ]]
  [[ "$output" == *'CheckServices="ssh,cron"'* ]]
}

@test "fails when SID missing" {
  run bash "$RENDER" "$CFG"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/render-config.bats`
Expected: FAIL (render-config.sh does not exist yet).

- [ ] **Step 3: Write minimal implementation**

`hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh`:
```bash
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
```
Make executable: `chmod +x hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/render-config.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: shellcheck**

Run: `shellcheck hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh tests/render-config.bats
git commit -m "feat: add tested hetrixtools.cfg renderer"
```

---

## Task 4: dry_run smoke test for the vendored agent (TDD)

**Files:**
- Test: `tests/dry-run.bats`

> Note: a full agent run needs host tools and ~60s. This test asserts only the **contract** the loop depends on: with `DryRun=1` and a rendered cfg, invoking the agent prints a `j=`-prefixed payload to stdout and exits without attempting a network POST. Run it where `bash`, `gzip`, `base64` exist; tolerate missing optional host tools.

- [ ] **Step 1: Write the test**

`tests/dry-run.bats`:
```bash
#!/usr/bin/env bats

setup() {
  AGENT="hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh"
  RENDER="hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh"
  WORK="$(mktemp -d)"
  cp "$AGENT" "$WORK/hetrixtools_agent.sh"
  SID="abcdefghijklmnopqrstuvwxyz012345" COLLECT_EVERY_SECONDS=3 \
    bash "$RENDER" "$WORK/hetrixtools.cfg"
}

teardown() { rm -rf "$WORK"; }

@test "dry_run prints payload and does not POST" {
  run env DryRun=1 timeout 90 bash "$WORK/hetrixtools_agent.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
  [[ "$output" == *"j="* ]]
}
```

- [ ] **Step 2: Run it**

Run: `bats tests/dry-run.bats`
Expected: PASS. If it FAILS because the agent expects extra writable paths/log files, adjust the test setup (e.g. pre-create expected log path under `$WORK`) — do **not** modify the agent beyond the Task 2 dry_run guard. Document any setup quirk in a comment.

- [ ] **Step 3: Commit**

```bash
git add tests/dry-run.bats
git commit -m "test: assert agent dry_run emits payload without POSTing"
```

---

## Task 5: s6-overlay v3 service (run script + loop guard)

**Files:**
- Create: `hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/type`
- Create: `hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run`
- Create: `hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/hetrixtools`

- [ ] **Step 1: Service type + registration**

`…/s6-rc.d/hetrixtools/type`:
```
longrun
```

`…/s6-rc.d/user/contents.d/hetrixtools` — empty file (registers the service):
```bash
touch hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/hetrixtools
```

- [ ] **Step 2: Write the run script**

`…/s6-rc.d/hetrixtools/run`:
```bash
#!/command/with-contenv bashio
# shellcheck shell=bash
set -e

LIB=/usr/lib/hetrixtools
RUN_DIR=/run/hetrixtools

# --- validate SID (fail fast, clear message) ---
SID="$(bashio::config 'sid')"
if [[ ! "$SID" =~ ^[A-Za-z0-9]{32}$ ]]; then
	bashio::exit.nok "Invalid or missing 'sid' (need a 32-char HetrixTools Server ID)."
fi

# --- render cfg next to a working copy of the agent ---
mkdir -p "$RUN_DIR"
cp "$LIB/hetrixtools_agent.sh" "$RUN_DIR/hetrixtools_agent.sh"

export SID
export COLLECT_EVERY_SECONDS; COLLECT_EVERY_SECONDS="$(bashio::config 'collect_every_seconds')"
export CHECK_DRIVE_HEALTH;    CHECK_DRIVE_HEALTH="$(bashio::config 'check_drive_health' | grep -q true && echo 1 || echo 0)"
export CHECK_SOFT_RAID;       CHECK_SOFT_RAID="$(bashio::config 'check_soft_raid' | grep -q true && echo 1 || echo 0)"
export CHECK_REBOOT;          CHECK_REBOOT="$(bashio::config 'check_reboot' | grep -q true && echo 1 || echo 0)"
export RUNNING_PROCESSES;     RUNNING_PROCESSES="$(bashio::config 'running_processes' | grep -q true && echo 1 || echo 0)"
export CONNECTION_PORTS;      CONNECTION_PORTS="$(bashio::config 'connection_ports' | tr '\n' ',' | sed 's/,$//')"
export CHECK_SERVICES;        CHECK_SERVICES="$(bashio::config 'check_services' | tr '\n' ',' | sed 's/,$//')"

bash "$LIB/render-config.sh" "$RUN_DIR/hetrixtools.cfg"

if bashio::config.true 'dry_run'; then
	export DryRun=1
	bashio::log.warning "dry_run enabled: payloads printed, not sent."
fi

bashio::log.info "Starting HetrixTools agent loop (SID ${SID:0:6}…)."

# --- loop with crash-loop guard: each cycle ~60s; backfill if it returns early ---
while true; do
	start=$(date +%s)
	bash "$RUN_DIR/hetrixtools_agent.sh" || bashio::log.warning "agent cycle exited non-zero"
	elapsed=$(( $(date +%s) - start ))
	if [ "$elapsed" -lt 55 ]; then
		sleep $(( 60 - elapsed ))
	fi
done
```
Make executable: `chmod +x hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run`

- [ ] **Step 3: shellcheck the run script**

Run: `shellcheck -s bash hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run`
Expected: clean (the `with-contenv bashio` shebang is non-standard; the `# shellcheck shell=bash` directive handles it).

- [ ] **Step 4: Commit**

```bash
git add hetrixtools-agent/rootfs/etc/s6-overlay
git commit -m "feat: add s6 service that renders cfg and loops the agent"
```

---

## Task 6: App manifest (`config.yaml`) + `repository.yaml`

**Files:**
- Create: `hetrixtools-agent/config.yaml`
- Create: `repository.yaml`

- [ ] **Step 1: Write `repository.yaml`**

```yaml
name: HetrixTools Agent for Home Assistant
url: https://github.com/owine/ha-hetrixtools-agent
maintainer: owine
```

- [ ] **Step 2: Write `config.yaml`**

```yaml
---
name: "HetrixTools Agent"
description: "Runs the HetrixTools server monitoring agent to report this Home Assistant host to HetrixTools"
version: "0.1.0" # x-release-please-version
slug: "hetrixtools_agent"
init: false
image: "ghcr.io/owine/hetrixtools-agent-{arch}"

arch:
  - aarch64
  - amd64

url: "https://github.com/owine/ha-hetrixtools-agent"

startup: services
boot: auto

# Host visibility: report the real HA OS host, not the container.
full_access: true
host_network: true
host_pid: true
udev: true

options:
  sid: ""
  collect_every_seconds: 3
  check_drive_health: false
  check_soft_raid: false
  check_reboot: false
  running_processes: false
  connection_ports: []
  check_services: []
  dry_run: false

schema:
  sid: "match(^[A-Za-z0-9]{32}$)"
  collect_every_seconds: "int(1,60)"
  check_drive_health: "bool"
  check_soft_raid: "bool"
  check_reboot: "bool"
  running_processes: "bool"
  connection_ports:
    - "str"
  check_services:
    - "str"
  dry_run: "bool"
```

- [ ] **Step 3: Validate YAML**

Run: `yamllint hetrixtools-agent/config.yaml repository.yaml`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add hetrixtools-agent/config.yaml repository.yaml
git commit -m "feat: add app manifest and repository metadata"
```

---

## Task 7: Dockerfile

**Files:**
- Create: `hetrixtools-agent/Dockerfile`

- [ ] **Step 1: Write the Dockerfile (no build.yaml — modern convention)**

```dockerfile
ARG BUILD_FROM
FROM ${BUILD_FROM}

# Tools the HetrixTools agent shells out to (host-facing via full_access/udev).
# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    coreutils \
    curl \
    wget \
    procps \
    util-linux \
    iproute2 \
    smartmontools \
    nvme-cli \
    lm-sensors \
    mdadm

COPY rootfs /

LABEL \
    io.hass.name="HetrixTools Agent" \
    io.hass.description="Runs the HetrixTools server monitoring agent for this HA host" \
    io.hass.type="addon" \
    io.hass.version="0.1.0" \
    org.opencontainers.image.source="https://github.com/owine/ha-hetrixtools-agent"
```

> Note: `gzip`/`base64` are provided by `coreutils`/busybox in the HA Alpine base; `vmstat`/`ps`/`pgrep` come from `procps`; `lsblk` from `util-linux`. `ipmitool` is intentionally omitted (not applicable on typical HA OS hardware; see spec open questions).

- [ ] **Step 2: hadolint**

Run: `hadolint hetrixtools-agent/Dockerfile`
Expected: clean (with `.hadolint.yaml` ignores).

- [ ] **Step 3: Commit**

```bash
git add hetrixtools-agent/Dockerfile
git commit -m "feat: add Dockerfile with agent tool dependencies"
```

---

## Task 8: Containerized smoke test (local build → dry_run)

**Files:**
- Create: `tests/smoke.sh`

- [ ] **Step 1: Write the smoke script**

`tests/smoke.sh`:
```bash
#!/usr/bin/env bash
# Build the amd64 image and verify the agent renders cfg + emits a payload in dry_run,
# WITHOUT depending on the HA supervisor (we invoke render + agent directly).
set -euo pipefail

BASE="ghcr.io/home-assistant/amd64-base:latest"
docker build \
  --build-arg BUILD_FROM="$BASE" \
  -t hetrixtools-agent:smoke \
  hetrixtools-agent

docker run --rm hetrixtools-agent:smoke bash -lc '
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
```
Make executable: `chmod +x tests/smoke.sh`

- [ ] **Step 2: Run it (requires Docker)**

Run: `./tests/smoke.sh`
Expected: ends with `SMOKE OK`. If the agent needs a writable working dir or a missing tool surfaces, fix the `docker run` setup (paths/permissions) — not the agent. Record any required tweak as a comment.

- [ ] **Step 3: Commit**

```bash
git add tests/smoke.sh
git commit -m "test: add containerized dry_run smoke test"
```

---

## Task 9: CI — lint + build/publish workflows

**Files:**
- Create: `.github/workflows/lint.yaml`
- Create: `.github/workflows/build.yaml`

- [ ] **Step 1: Lint workflow**

`.github/workflows/lint.yaml`:
```yaml
---
name: Lint
on:
  push:
    branches: [main]
  pull_request:
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: shellcheck
        run: |
          sudo apt-get update && sudo apt-get install -y shellcheck
          shellcheck -x hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh
          shellcheck -s bash hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run
      - name: hadolint
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: hetrixtools-agent/Dockerfile
      - name: yamllint
        run: |
          sudo apt-get install -y yamllint
          yamllint hetrixtools-agent/config.yaml repository.yaml .github
      - name: bats
        run: |
          sudo apt-get install -y bats
          bats tests/render-config.bats tests/dry-run.bats
```

- [ ] **Step 2: Build/publish workflow (home-assistant/builder → GHCR)**

`.github/workflows/build.yaml`:
```yaml
---
name: Build
on:
  push:
    branches: [main]
    paths: ["hetrixtools-agent/**"]
  release:
    types: [published]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      matrix:
        arch: [aarch64, amd64]
    steps:
      - uses: actions/checkout@v4
      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build & push ${{ matrix.arch }}
        uses: home-assistant/builder@master
        with:
          args: |
            --${{ matrix.arch }} \
            --target /data/hetrixtools-agent \
            --image "hetrixtools-agent-{arch}" \
            --docker-hub "ghcr.io/owine" \
            --addon
```

> Verify the exact `home-assistant/builder` flags against its current README during implementation (flag names occasionally change); the intent is per-arch build of `hetrixtools-agent/` published to `ghcr.io/owine/hetrixtools-agent-{arch}`, matching `config.yaml`'s `image:`.

- [ ] **Step 3: Validate workflow YAML**

Run: `yamllint .github/workflows`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows
git commit -m "ci: add lint and GHCR build/publish workflows"
```

---

## Task 10: release-please + renovate

**Files:**
- Create: `release-please-config.json`, `.release-please-manifest.json`
- Create: `renovate.json`
- Create: `.github/workflows/release-please.yaml`

- [ ] **Step 1: release-please config**

`release-please-config.json`:
```json
{
  "packages": {
    "hetrixtools-agent": {
      "release-type": "simple",
      "package-name": "hetrixtools-agent",
      "changelog-path": "CHANGELOG.md",
      "extra-files": ["config.yaml", "Dockerfile"]
    }
  },
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
```

`.release-please-manifest.json`:
```json
{ "hetrixtools-agent": "0.1.0" }
```

`.github/workflows/release-please.yaml`:
```yaml
---
name: release-please
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

> Ensure the `# x-release-please-version` marker is on `config.yaml`'s `version:` line (Task 6) and add one on the Dockerfile `io.hass.version` LABEL so both bump together.

- [ ] **Step 2: renovate config**

`renovate.json`:
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/hetrixtools-agent/upstream-agent.version/"],
      "matchStrings": ["^(?<currentValue>.*)$"],
      "depNameTemplate": "hetrixtools/agent",
      "datasourceTemplate": "github-tags"
    }
  ]
}
```

> Renovate will PR new upstream agent tags by bumping `upstream-agent.version`. The PR is a signal to re-vendor (Task 2) and re-apply the dry_run patch via the `>>> ha-app patch >>>` markers. Document this in `DOCS.md`.

- [ ] **Step 3: Validate**

Run: `yamllint .github/workflows/release-please.yaml && python3 -c "import json;[json.load(open(f)) for f in ['release-please-config.json','.release-please-manifest.json','renovate.json']]"`
Expected: no output / no errors.

- [ ] **Step 4: Commit**

```bash
git add release-please-config.json .release-please-manifest.json renovate.json .github/workflows/release-please.yaml
git commit -m "ci: add release-please and renovate automation"
```

---

## Task 11: Documentation & branding

**Files:**
- Create: `hetrixtools-agent/DOCS.md`, `hetrixtools-agent/README.md`, `hetrixtools-agent/CHANGELOG.md`
- Create: `README.md` (repo root)
- Create: `hetrixtools-agent/icon.png`, `hetrixtools-agent/logo.png` (placeholders)

- [ ] **Step 1: `DOCS.md`** — cover: getting a SID (create a HetrixTools Uptime Monitor → Install Monitoring Agent → copy the 32-char SID), installing the app, setting options, the HA OS caveats (sensors depend on hardware; `check_reboot`/`check_services` limited; IPMI N/A), one-monitor-per-SID, `dry_run` for debugging, and the renovate re-vendor flow.

- [ ] **Step 2: `README.md` (app + root)** — short overview, install via repo URL, link to DOCS.

- [ ] **Step 3: `CHANGELOG.md`** — seed:
```markdown
# Changelog

## 0.1.0
- Initial release: HetrixTools monitoring agent as a Home Assistant app.
```

- [ ] **Step 4: Branding placeholders** — add `icon.png` (256×256) and `logo.png`. If no art yet, add a `BRANDING.md` TODO and a plain placeholder so the store renders; replace before publishing.

- [ ] **Step 5: Commit**

```bash
git add hetrixtools-agent/DOCS.md hetrixtools-agent/README.md hetrixtools-agent/CHANGELOG.md README.md hetrixtools-agent/icon.png hetrixtools-agent/logo.png
git commit -m "docs: add user docs, README, changelog, and branding placeholders"
```

---

## Task 12: Final verification

- [ ] **Step 1: Run all local gates**

Run:
```bash
shellcheck -x hetrixtools-agent/rootfs/usr/lib/hetrixtools/render-config.sh
shellcheck -s bash hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run
hadolint hetrixtools-agent/Dockerfile
yamllint hetrixtools-agent/config.yaml repository.yaml .github
bats tests/render-config.bats tests/dry-run.bats
./tests/smoke.sh
```
Expected: all pass; smoke ends `SMOKE OK`.

- [ ] **Step 2: Manual acceptance (real HA OS, post-merge)**

In Home Assistant: Settings → Apps → app store → add repo `https://github.com/owine/ha-hetrixtools-agent` → install **HetrixTools Agent** → set `sid` → Start. Confirm host data appears in the HetrixTools dashboard within ~2 minutes. Record the result in the PR.

- [ ] **Step 3: Finalize**

Use superpowers:finishing-a-development-branch to open the PR.

---

## Notes for the implementer

- **Do not modify the vendored agent** beyond the Task 2 `dry_run` guard. Keep the patch inside the `>>> ha-app patch >>>` markers so future upstream bumps are re-patchable.
- **TDD anchor:** `render-config.sh` (Task 3) is the genuinely unit-testable unit — keep it pure. The dry_run/smoke tests assert the loop's contract, not full host collection (which needs real hardware).
- **Verify external flag names live:** `home-assistant/builder` args and the HA base image tag should be confirmed against current docs during Task 9/7 (use context7 / the builder README) rather than trusted from this plan.
- **HA OS realism:** missing sensors/IPMI/reboot-required are expected, not bugs — the agent omits absent metrics.
