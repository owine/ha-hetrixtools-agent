# Changelog

## [0.3.0](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.2.3...hetrixtools-agent-v0.3.0) (2026-11-07)

**1 feature · 7 bug fixes · 1 dependency update**

### ✨ Features

- re-vendor HetrixTools agent 2.4.2 (SAS and RAID drive health) ([#78](https://github.com/owine/ha-hetrixtools-agent/issues/78))
  - With `check_drive_health` on, SAS drives now report their health, including drives behind MegaRAID and HP Smart Array RAID controllers
  - A drive seen through more than one path is listed once
  - A comma or semicolon in a drive's model or serial number no longer garbles the drive list

### 🐛 Bug Fixes

- let Renovate detect the vendored HetrixTools agent version ([#77](https://github.com/owine/ha-hetrixtools-agent/issues/77))
- pass the TCP probe target to bash -c as arguments ([#73](https://github.com/owine/ha-hetrixtools-agent/issues/73))
  - The host and port of a TCP ping target are passed to the probe as data, never as shell code
- replace control characters in the debug log before the Log tab ([#72](https://github.com/owine/ha-hetrixtools-agent/issues/72))
  - With `debug` on, control characters (such as terminal escape codes) in probe output are replaced before they reach the **Log** tab
- raw probe output can no longer start a line in the debug log ([#71](https://github.com/owine/ha-hetrixtools-agent/issues/71))
  - With `debug` on, ping and TCP probe output is indented, so it can no longer pose as a line of the app's own log
- a missing ignored_disks no longer replaces the disk filter with 'null' ([#66](https://github.com/owine/ha-hetrixtools-agent/issues/66))
  - If `ignored_disks` was cleared, the app could report its own container overlay as a host disk; an empty or missing value now always means the default filter
  - A line break in an option value now stops the app with a clear error instead of being written into the agent's settings
- pass the ping RTT to awk as data, not program text ([#63](https://github.com/owine/ha-hetrixtools-agent/issues/63))
- keep the full SID out of the dry_run and debug logs ([#62](https://github.com/owine/ha-hetrixtools-agent/issues/62))
  - With `debug` or `dry_run` on, the **Log** tab now shows only the first six characters of your `sid`, so logs are safer to share in bug reports
  - `dry_run` now shows the payload as readable JSON instead of an encoded string
  - The documentation now warns against posting your full `sid` or `hetrixtools.cfg`

### 📦 Dependencies

- update ghcr.io/home-assistant/base:3.24 docker digest to 5842248 ([#60](https://github.com/owine/ha-hetrixtools-agent/issues/60), [#70](https://github.com/owine/ha-hetrixtools-agent/issues/70))

## [0.2.3](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.2.2...hetrixtools-agent-v0.2.3) (2026-10-28)

**1 bug fix · 2 dependency updates**

### 🐛 Bug Fixes

- drop host_pid so the app boots with protection mode off ([#59](https://github.com/owine/ha-hetrixtools-agent/issues/59))
  - The app starts with protection mode off again. It used to request the host's process namespace, which the Supervisor grants only with protection mode off, and the app's init system refuses to run inside it.
  - SMART drive health now gets the capabilities it needs: `SYS_RAWIO` for SATA disks and `SYS_ADMIN` for NVMe drives. Drive health and software RAID status still need protection mode off, which gives the app access to the disks.
  - ICMP outgoing pings now request the `NET_RAW` capability explicitly, so they keep working once the Supervisor stops granting it by default.
  - The Configuration tab now shows a readable name and help text for every option.
  - `running_processes` and `check_services` see only the app's own processes. This was already true with protection mode on.
  - The documentation explains what protection mode changes and why the app asks for each privilege, and has new troubleshooting and support sections.
  - The app is now MIT licensed. The bundled HetrixTools agent script stays under HetrixTools' own terms.

### 📦 Dependencies

- update ghcr.io/home-assistant/base:3.24 docker digest to 89f3a85 ([#55](https://github.com/owine/ha-hetrixtools-agent/issues/55), [#58](https://github.com/owine/ha-hetrixtools-agent/issues/58))
- update curl apk package to v8.23.0-r0 ([#54](https://github.com/owine/ha-hetrixtools-agent/issues/54))

## [0.2.2](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.2.1...hetrixtools-agent-v0.2.2) (2026-10-13)


### Bug Fixes

* **s6:** define the user bundle in user-bundles.d ([13ee6a9](https://github.com/owine/ha-hetrixtools-agent/commit/13ee6a9acca473928ab69d6803ec0f0688a88d3f))
* **s6:** start the agent after the base bundle ([421cf6e](https://github.com/owine/ha-hetrixtools-agent/commit/421cf6e9646784e5789eac78d65631a1a4d7c6ee))

## [0.2.1](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.2.0...hetrixtools-agent-v0.2.1) (2026-10-12)


### Dependencies

* update ghcr.io/home-assistant/base:3.24 docker digest to 8fde417 ([#44](https://github.com/owine/ha-hetrixtools-agent/issues/44)) ([56b4f3e](https://github.com/owine/ha-hetrixtools-agent/commit/56b4f3eb2269120604d91b38645c017433b1e428))

## [0.2.0](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.1.2...hetrixtools-agent-v0.2.0) (2026-09-17)


### Features

* expose outgoing ping latency targets ([#41](https://github.com/owine/ha-hetrixtools-agent/issues/41)) ([ab41245](https://github.com/owine/ha-hetrixtools-agent/commit/ab412450b02db742562fc324f2e923770de1bb7e))


### Bug Fixes

* exclude the container overlay root from disk reporting, add debug option ([5681f34](https://github.com/owine/ha-hetrixtools-agent/commit/5681f341d472deb7be434e120c7c4d5fd84474f5))
* report only host NICs, not Docker's ephemeral veth pairs ([acea8c6](https://github.com/owine/ha-hetrixtools-agent/commit/acea8c60133cb06617d511d3297b2e5411be75d3))

## [0.1.2](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.1.1...hetrixtools-agent-v0.1.2) (2026-09-17)


### Dependencies

* update dependency alpine_3_24/curl to v8.22.0-r0 ([#32](https://github.com/owine/ha-hetrixtools-agent/issues/32)) ([5a22a4c](https://github.com/owine/ha-hetrixtools-agent/commit/5a22a4ccfa1e9339a0417ab0c2c19a997a332fe2))
* update dependency alpine_3_24/util-linux to v2.42.3-r0 ([#34](https://github.com/owine/ha-hetrixtools-agent/issues/34)) ([cd05042](https://github.com/owine/ha-hetrixtools-agent/commit/cd050426bda5d7e6f0a7362b15f9a961262b4a71))
* update dependency alpine_3_24/util-linux to v2.42.3-r1 ([#35](https://github.com/owine/ha-hetrixtools-agent/issues/35)) ([a92f3ea](https://github.com/owine/ha-hetrixtools-agent/commit/a92f3ea9f8da069285009f660830a7edccb4cc89))

## [0.1.1](https://github.com/owine/ha-hetrixtools-agent/compare/hetrixtools-agent-v0.1.0...hetrixtools-agent-v0.1.1) (2026-08-20)


### Dependencies

* update ghcr.io/home-assistant/base:3.24 docker digest to 93ef607 ([#28](https://github.com/owine/ha-hetrixtools-agent/issues/28)) ([526e27e](https://github.com/owine/ha-hetrixtools-agent/commit/526e27e3a21b38c93a4f1eeabd101c75ac83f83d))

## 0.1.0 (2026-06-21)

Initial release: the HetrixTools monitoring agent as a Home Assistant app.

### Features

* add app manifest and repository metadata ([6f4602b](https://github.com/owine/ha-hetrixtools-agent/commit/6f4602bdb40448979c58164ac96d761171ca6247))
* add Dockerfile with agent tool dependencies ([ac60c71](https://github.com/owine/ha-hetrixtools-agent/commit/ac60c715cb1ec870f6e520451588917ad9912459))
* add owine-branded icon and logo ([#15](https://github.com/owine/ha-hetrixtools-agent/issues/15)) ([8307125](https://github.com/owine/ha-hetrixtools-agent/commit/8307125254a8dbee8bfc5763ea7b56269da1a349))
* add s6 service that renders cfg and loops the agent ([9286de5](https://github.com/owine/ha-hetrixtools-agent/commit/9286de5e044fc4a6b40e063603756a835d1c9b16))
* add tested hetrixtools.cfg renderer ([7a7c450](https://github.com/owine/ha-hetrixtools-agent/commit/7a7c45043d8e5a9cf65ad67d17dc2a669ce29745))
* vendor HetrixTools agent v2.4.1 with dry_run guard ([9805a4e](https://github.com/owine/ha-hetrixtools-agent/commit/9805a4eeed8e8897838bbb7f4b32db29cafa4e29))

### Bug Fixes

* add GNU grep for agent IP collection; clean up smoke test entrypoint ([2a99b38](https://github.com/owine/ha-hetrixtools-agent/commit/2a99b38fca7e47905ae0ce3ab273b61ea250afcf))
* build each arch on a native runner via prepare-multi-arch-matrix ([dce347b](https://github.com/owine/ha-hetrixtools-agent/commit/dce347bf575c29a9299f21e453d59a06e302dc9d))
* harden s6 run loop with pipefail and negative-elapsed guard ([11feff2](https://github.com/owine/ha-hetrixtools-agent/commit/11feff25f8c5bb6fafd7451aa0447d408a8ec29a))
* ship a single multi-arch image (no {arch}) ([#18](https://github.com/owine/ha-hetrixtools-agent/issues/18)) ([57b23f9](https://github.com/owine/ha-hetrixtools-agent/commit/57b23f9d10e2a23205e1af1ddee9ac7a70da42cd))
* use valid x-release-please block markers for Dockerfile version ([87ca785](https://github.com/owine/ha-hetrixtools-agent/commit/87ca785445d6ddd9d714fd15d40dc734895fa46e))
