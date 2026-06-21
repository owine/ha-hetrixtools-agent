# HetrixTools Agent — Home Assistant App Design

**Date:** 2026-06-21
**Status:** Approved (pending spec review)
**Author:** owine (with Claude Code)

## Summary

A Home Assistant **app** (formerly "add-on"; renamed in HA 2026.1) that runs the
[HetrixTools server monitoring agent](https://github.com/hetrixtools/agent) inside a
privileged container so it reports the **real Home Assistant OS host** — CPU, RAM, disks,
SMART/drive health, software RAID, temperatures, network, uptime — to the HetrixTools
uptime/monitoring platform.

The HetrixTools agent is normally a root-level bash daemon installed directly on a Linux
host, scheduled by cron/systemd, with a built-in self-updater. This app inverts that model:
the agent runs as root **inside a container that is granted a window into the host**, the
container's service supervisor replaces cron/systemd, and updates ship as app updates
(self-update disabled).

## Goals

- Report genuine HA OS **host** metrics to HetrixTools, not container-only stats.
- Ship as a **publishable** app: GHCR-published images, store metadata, release automation,
  linting — mirroring the structure of the maintainer's `claude-terminal-home-assistant`
  repo, but using **modern 2026 app conventions**.
- Configure entirely through the Apps panel (no shell access required from the user).

## Non-Goals

- Replacing or wrapping HetrixTools' web dashboard/API.
- Supporting non-Supervisor installs (plain Docker / Core). Target is **HA OS**.
- Exposing a web UI / ingress — this is a headless daemon.
- Reproducing the agent's self-update or cron/systemd scheduling.

## Context & Key Facts

### The HetrixTools agent
- 100% bash. POSTs gzipped+base64 JSON to `https://sm.hetrixtools.net/v2/` (field `j=...`),
  identified by a 32-char **SID** (Server ID; one per HetrixTools Uptime Monitor).
- Reads host signals: `/proc/{stat,meminfo,loadavg,uptime,diskstats,net/dev,mdstat}`,
  `/sys/class/thermal`, `/sys/class/hwmon`, and shells out to `vmstat`, `lsblk`, `df`, `ip`,
  `ss`/`netstat`, `sensors`, `smartctl`, `nvme`, `zpool`, `mdadm`, `ps`, `pgrep`, `lscpu`,
  `ipmitool`.
- One invocation collects `60 / CollectEveryXSeconds` samples over ~60s, then POSTs once and
  exits. Upstream relies on cron/systemd to re-invoke every minute.
- Config file `hetrixtools.cfg`: `SID`, `CollectEveryXSeconds`, `CheckServices`,
  `CheckSoftRAID`, `CheckDriveHealth`, `CheckReboot`, `RunningProcesses`, `ConnectionPorts`.
- Requires root for full visibility (SMART, RAID, sensors).

### Modern HA "apps" conventions (verified against developers.home-assistant.io, 2026.1+)
- Add-ons were renamed **apps** in HA 2026.1; surfaced in the native **Apps panel**.
- Manifest is still **`config.yaml`**; repo metadata is still **`repository.yaml`**.
- Field names unchanged: `slug`, `arch`, `startup`, `boot`, `host_network`, `host_pid`,
  `full_access`, `privileged`, `devices`, `udev`, `map`, `options`, `schema`, `image`.
- **`build.yaml` is removed.** Build inputs (`build_from`, `args`, `labels`) now live directly
  in the `Dockerfile` via `ARG BUILD_FROM` / `FROM ${BUILD_FROM}` / `LABEL`.
- Modern apps publish **prebuilt container images** to a registry (GHCR) via the
  `home-assistant/builder` GitHub Action and reference them with `image:` (+ `version` = tag).
- Modern `map` uses object form (`type:`/`read_only:`); legacy `config:rw` strings are
  deprecated. **This app needs no `map`** — host access comes via `full_access`/`host_pid`/
  `devices`, not HA-managed shares.

## Architecture

### Repository layout

```
ha-hetrixtools-agent/
├── repository.yaml                 # app store metadata (name/url/maintainer)
├── hetrixtools-agent/              # the app
│   ├── config.yaml                 # slug, arch, image, options, schema, privileges
│   ├── Dockerfile                  # ARG BUILD_FROM + FROM + LABELs (no build.yaml)
│   ├── rootfs/
│   │   └── etc/s6-overlay/s6-rc.d/hetrixtools/   # s6-overlay v3 service
│   ├── hetrixtools_agent.sh        # vendored, pinned, scheduler/self-update stripped
│   ├── DOCS.md / README.md / CHANGELOG.md
│   └── icon.png / logo.png
├── .github/workflows/              # builder → GHCR publish; lint
├── release-please-config.json + .release-please-manifest.json
├── renovate.json
└── lint configs (.shellcheckrc, .hadolint.yaml, .yamllint)
```

### Host visibility

`config.yaml` requests, so the container reports the host rather than itself:

- `full_access: true` — hardware-level access.
- `host_network: true` — real host interfaces/`/proc/net/dev`.
- `host_pid: true` — host process namespace for `/proc/*`, `ps`/`pgrep`.
- `devices` / `udev: true` — `/dev` block devices for `smartctl`, `nvme`, `lsblk`.

The agent's CLI tool dependencies are installed **inside the image** (not assumed on the
host): `smartmontools`, `lm-sensors`, `util-linux`, `iproute2`, `nvme-cli`, `mdadm`, and
optionally `ipmitool`. Any missing tool or unreadable host signal results in that metric
being **omitted**, never a crash.

**HA OS realism:** CPU/RAM/disk/SMART/RAID surface reliably; temperatures depend on the
hardware's `hwmon`; IPMI typically does not apply (NUC/Pi). `CheckReboot` is usually a no-op
on HA OS (no `reboot-required` file). Host **systemd service state** is not reliably queryable
from the container, so `CheckServices` works only for `pgrep`-style process matching.

## Configuration (app options → `hetrixtools.cfg`)

`run`/`run.sh` (via `bashio`) renders options into `/etc/hetrixtools/hetrixtools.cfg`:

| App option | Type / default | cfg field | Notes |
|---|---|---|---|
| `sid` | str, **required**, `match(^[A-Za-z0-9]{32}$)` | `SID` | Fail fast if absent/malformed |
| `collect_every_seconds` | int, default `3` | `CollectEveryXSeconds` | |
| `check_drive_health` | bool, default `false` | `CheckDriveHealth` | needs `smartctl` + `/dev` |
| `check_soft_raid` | bool, default `false` | `CheckSoftRAID` | `/proc/mdstat`, `mdadm` |
| `check_reboot` | bool, default `false` | `CheckReboot` | usually no-op on HA OS |
| `running_processes` | bool, default `false` | `RunningProcesses` | host procs via `host_pid` |
| `connection_ports` | list[str], default `[]` | `ConnectionPorts` | |
| `check_services` | list[str], default `[]` | `CheckServices` | `pgrep` matching only (caveat above) |
| `dry_run` | bool, default `false` | n/a (wrapper) | print payload instead of POSTing |

## Runtime / service

- Modern **s6-overlay v3** longrun service at
  `rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run`; `init: false`, `startup: services`,
  `boot: auto`.
- Service flow:
  1. Read options via `bashio::config`.
  2. Validate `sid` (present + 32 chars) — `bashio::exit.nok` with a clear message otherwise.
  3. Render `/etc/hetrixtools/hetrixtools.cfg` from a template + options.
  4. `while true; do bash hetrixtools_agent.sh; done` — each invocation is one ~60s
     collect-then-POST cycle, yielding continuous minute-by-minute reporting without an
     external scheduler.
- `dry_run=true` sets an env flag that makes the agent print the JSON payload instead of
  POSTing (used by CI smoke test and local debugging).

## Vendoring the agent

- Commit a **pinned** copy of `hetrixtools_agent.sh` into the app folder.
- Strip/disable: the self-update path and any cron/systemd scheduling assumptions; verify the
  collect-then-POST cycle runs cleanly when invoked directly and when optional tools are absent.
- Record the upstream version/commit in a marker that renovate's custom regex manager tracks,
  so dependency bumps surface as PRs.

## Build, CI, versioning

- **Dockerfile:** `ARG BUILD_FROM` / `FROM ${BUILD_FROM}` (HA Alpine base), `apk add` the tool
  deps, copy vendored agent + `rootfs`, set OCI + `io.hass.*` `LABEL`s. No `build.yaml`.
- **Publish CI:** `home-assistant/builder` builds per-arch (`aarch64`, `amd64`) and pushes to
  `ghcr.io/owine/hetrixtools-agent`; `config.yaml` `image:` references it with `version` = tag.
- **release-please** manages `version` (via `x-release-please-version` marker) and `CHANGELOG.md`.
- **renovate** tracks the base image, GitHub Actions, and the vendored agent version.
- **Lint CI:** `shellcheck`, `hadolint`, `yamllint`.

## Testing

- CI lint gates: shellcheck (run/agent scripts), hadolint (Dockerfile), yamllint (YAML).
- **Containerized smoke test** (amd64): build the image, run with a dummy SID and
  `dry_run=true`; assert it renders a valid `hetrixtools.cfg` and emits parseable JSON without
  crashing when host tools/signals are missing.
- **Manual acceptance** on real HA OS: add this repo to the Apps store, install, set SID,
  confirm data appears in the HetrixTools dashboard within ~2 minutes.

## Error handling & edge cases

- Missing/invalid SID → `bashio::exit.nok` with a clear log line; service does not loop.
- Missing tool / unreadable host path → metric omitted; no crash.
- POST failure → agent's `wget` retries (`--retry-connrefused -t 3 -T 15`); we log and continue.
- One HetrixTools monitor = one SID = one agent. Multiple HA hosts need separate monitors/SIDs
  (documented in `DOCS.md`).
- Self-update disabled; updates ship as app updates (documented).

## Open questions / future work

- Whether to expose `ipmitool` install behind an option to keep the default image lean.
- Optional health/notification surface (e.g. log a warning if N consecutive POSTs fail).
