# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Home Assistant app repository (HA now says "app" for what it used to call an "add-on") holding one app, `hetrixtools-agent/`. It runs the upstream HetrixTools monitoring agent, a single bash script, on the HA OS host. The app is a packaging shim around that script. Our own code is the s6 run script, three small helper scripts, the Dockerfile, and the CI/release machinery.

## Commands

Run everything from the repo root; tests use repo-relative paths.

```sh
# Unit tests (bats). CI runs this exact list in .github/workflows/lint.yaml
bats tests/render-config.bats tests/detect-interfaces.bats tests/debug-log-filter.bats \
  tests/ping-rtt.bats tests/probe-debug-log.bats tests/tcp-probe.bats \
  tests/release-gate.bats tests/upstream-delta.bats tests/renovate-config.bats \
  tests/dry-run.bats tests/docs-agent-version.bats

# One file, or one test by name
bats tests/render-config.bats
bats tests/render-config.bats -f "line break"

# Lint (mirrors CI)
(cd hetrixtools-agent/rootfs/usr/lib/hetrixtools && shellcheck -x render-config.sh detect-interfaces.sh debug-log-filter.sh)
shellcheck -s bash hetrixtools-agent/rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run
shellcheck tests/smoke.sh tests/boot.sh .github/scripts/release-gate.sh
hadolint -c .hadolint.yaml hetrixtools-agent/Dockerfile
yamllint hetrixtools-agent/config.yaml hetrixtools-agent/translations repository.yaml .github

# Vendored agent vs upstream (Lint's last step; run it after touching the agent or
# re-vendoring). The download is only hashed and read as text, never run.
d="$(mktemp -d)"; v="$(cat hetrixtools-agent/upstream-agent.version)"
curl -fsSL --retry 3 -o "$d/upstream.sh" \
  "https://raw.githubusercontent.com/hetrixtools/agent/refs/tags/$v/hetrixtools_agent.sh"
echo "$(cat hetrixtools-agent/upstream-agent.sha256)  $d/upstream.sh" | shasum -a 256 -c - &&
  python3 -I tests/upstream-delta.py "$d/upstream.sh" \
    hetrixtools-agent/rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh hetrixtools-agent/upstream-agent.patches

# Docker-based (need Docker; slow)
tests/smoke.sh   # build amd64, render cfg + run one agent cycle in dry_run, bypassing s6
tests/boot.sh    # boot through real s6-overlay + bashio against a stub Supervisor (BOOT_PLATFORM=linux/arm64 for arm)
```

CI runs shellcheck on the helper scripts by name and never on `hetrixtools_agent.sh`, so don't lint or "fix" the vendored agent.

Tests that execute the agent need bash ≥ 4, and `dry-run.bats` also needs Linux `/proc`. On macOS's stock bash 3.2 they skip rather than fail, so a green local run does not mean they ran. `renovate-config.bats` skips without `node`.

`lint.yaml` names every shellcheck target and every `.bats` file, with no globs. **A new shell script is not shellchecked, and a new `.bats` file is not run, until it is added to `.github/workflows/lint.yaml`.**

## Runtime architecture

The base image's s6-overlay starts `rootfs/etc/s6-overlay/s6-rc.d/hetrixtools/run` (a `bashio` script), which:

1. Validates `sid` and reads every app option via bashio into env vars (booleans → `0`/`1`, lists → joined strings; `outgoing_pings` entries are joined with `|` because entries themselves contain commas).
2. Pipes `ip a` through `detect-interfaces.sh` to pin real host NICs. Without the pin, the agent's own auto-detect picks up Docker `veth*` interfaces that vanish mid-sample. Empty output deliberately falls back to the agent's auto-detect.
3. Calls `render-config.sh`, a pure env→`hetrixtools.cfg` renderer. It refuses any value containing a line break, which would inject a cfg line. Its `IgnoredDisks` default carries upstream's four terms forward plus `^overlay`, because setting the option *replaces* upstream's default.
4. Copies the agent to `/run/hetrixtools/` next to the cfg and loops it forever. Each agent invocation self-paces to about 60s; the loop's sleep only stops a crashing agent from hitting the API repeatedly. After each cycle, `debug.log` passes through `debug-log-filter.sh`, which shortens the SID and neutralises control characters, and is then truncated.

**Adding or changing an option** touches several files that must stay in sync. Under `hetrixtools-agent/`: `config.yaml` (`options` + `schema`), `translations/en.yaml`, the `run` script, and `DOCS.md`. In `tests/`: the options stub in `boot.sh`. An option the agent reads from the cfg also needs `render-config.sh` (both the template *and* the line-break guard's variable list; a bats test checks the two lists match) and an expected-output assertion in `tests/render-config.bats`, since nothing else checks how the option is rendered. An app-only option never reaches the cfg: `dry_run`, for example, is exported by `run` as `DryRun=1` for the agent to read from its environment.

The `config.yaml` comments record why the container gets each privilege (`full_access`, `host_network`, `udev`, the `privileged` caps) and why `host_pid` must stay off, since s6 has to be PID 1. `tests/boot.sh` parses `config.yaml` to reproduce the Supervisor's grants with protection mode on and off. Keep those keys as plain `true`/`false` and `privileged` as a block list, or boot.sh refuses to parse them.

## The vendored agent (`rootfs/usr/lib/hetrixtools/hetrixtools_agent.sh`)

Copyright HetrixTools, not MIT. It must be the upstream release named in `upstream-agent.version`, byte for byte, except inside `# >>> ha-app patch: <title> >>>` … `# <<< ha-app patch <<<` blocks. `upstream-agent.patches` declares each block (number of upstream lines it replaces, a hash, a title). `upstream-agent.sha256` pins the upstream file. Lint's "vendored agent vs upstream" step downloads upstream and runs `tests/upstream-delta.py` to enforce this.

- Never edit the agent outside a patch block. To change behaviour, add or extend a block, then regenerate the manifest with `python3 -I tests/upstream-delta.py --suggest <upstream> <vendored>` and review the output.
- Re-vendoring (triggered by a Renovate PR that bumps only `upstream-agent.version`, which never automerges): fetch the new upstream, re-apply every block, update `.sha256` and `.patches`, and update the agent version wherever `hetrixtools-agent/DOCS.md` names it (CI fails until all three match; `tests/docs-agent-version.bats` covers DOCS.md). By hand, with no check to catch a miss, also update the patch list in that file's "Maintenance and updates" section and the one in the description of the `hetrixtools/agent` rule in `renovate.json`.
- The SID is the server's only credential. Nothing the app logs may contain it in full; the shortened form is the first 6 chars + `…`. Several patches and `debug-log-filter.sh` exist for this; `dry-run.bats`, `smoke.sh` and `debug-log-filter.bats` check it.

## Image and dependencies

- `Dockerfile`: the base is pinned by tag + digest. Every `apk add` package is pinned to an exact version. Alpine purges old builds from its index, so a stale pin breaks the build, and Renovate co-bumps all pins in one grouped PR. When the base crosses an Alpine release line, change `branch=v3.XX` in `renovate.json`'s apk `registryUrls` to match; it is the only setting that names the line, and Renovate won't change it for you. (A Dockerfile comment quotes the current branch too; update it in the same PR.)
- The image needs GNU grep (PCRE `-oP`), procps-ng, and iputils-ping (the agent parses iputils' `rtt min/avg/max` line; BusyBox's output silently yields 0 ms).
- The `APK_REFRESH` build arg is set to a unique value only on releases, so each release re-runs `apk upgrade` instead of reusing a cached layer with stale transitive packages.
- `renovate.json` extends `owine/renovate-config` presets. `hetrixtools/agent` and `home-assistant/builder` are deliberately never automerged; the reasons are in each rule's `description`.

## Release flow (don't bump versions by hand)

1. release-drafter keeps a draft release (`hetrixtools-agent-vX.Y.Z`) built from merged PR titles, which use conventional-commit types (`feat:`, `fix:`, `deps:`, `ci:`, `chore:`). PR titles become user-facing release notes.
2. Publishing that release triggers `.github/workflows/build.yaml`. `.github/scripts/release-gate.sh` (run in every pushing job) refuses prereleases, tags not on main, and versions older than what HA offers. The workflow then builds and pushes per-arch images natively (no QEMU), publishes the multi-arch manifest, and signs with cosign.
3. The `promote` job, via a GitHub App, then commits `chore(release): publish X.Y.Z to add-on store` to main. That commit bumps `config.yaml`'s `version` and prepends the release notes to `CHANGELOG.md`. The Supervisor reads `config.yaml` from main, so the store never offers an image that can't be pulled.

So `config.yaml` `version` and `CHANGELOG.md` are written by the bot; don't edit them in feature PRs. The runner OS for Build's `build` job comes from the pinned `home-assistant/builder` action rather than from any `runs-on:` in this repo.

`Boot` (`tests/boot.sh` on amd64 + arm64) runs on PRs and its job names are required status checks in the main ruleset. Renaming those jobs or changing the matrix arch values means updating the ruleset.

## Conventions

Comments in this repo explain *why*: the failure mode a line prevents, often with the incident behind it. Keep that style when changing code, and keep existing rationale comments accurate when behaviour changes.
