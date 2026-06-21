# Changelog

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
