# Home Assistant base image — multi-arch minimal Alpine; buildx selects the arch
# per native-runner build. Pinned to a tag + digest (Renovate keeps the digest
# current). For local testing you can override with a plain tag (no digest), e.g.
#   --build-arg BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24@sha256:58422480a299b16b6ea376c2167463206d430619ed02b40cd687c8bd6875519e
FROM ${BUILD_FROM}

# Tools the HetrixTools agent shells out to (host-facing via full_access/udev).
# GNU grep is required: the agent uses `grep -oP … \K` (PCRE) to extract host
# IPv4/IPv6 addresses, which the base image's BusyBox grep cannot do. procps-ng
# likewise supplies the `ps -eo`/`vmstat` BusyBox lacks.
#
# iputils-ping replaces BusyBox's ping: the agent parses latency from an
# `rtt min/avg/max/mdev` line, which only iputils emits. BusyBox prints
# `round-trip min/avg/max` instead, so outgoing ping targets would report a
# plausible-looking 0 ms rather than failing visibly.
#
# Versions are pinned and kept current by Renovate, which extracts these
# `apk add` pins natively (datasource `apk`). Alpine's index keeps only the
# newest build of each apk and purges the rest, so a drifted pin fails the build
# rather than silently installing something stale — every pin must co-bump in
# one PR, which is what the shared :alpine preset's grouping guarantees. When
# the base image crosses a release line, update the `branch=v3.24` in
# renovate.json's apk registryUrls to match. The `apk upgrade` below moves base
# packages forward too, including bash and curl, which the base already ships;
# that is the same failure, surfacing for a pin that has fallen behind the
# index, and the fix is the same Renovate bump.
#
# APK_REFRESH makes a release rebuild this layer. build-image reuses cached
# layers (the GitHub Actions cache and the registry's :latest), and the pins
# above name direct packages only: with no pin changed, a release reuses the
# cached layer, so transitive packages never pick up Alpine's security fixes,
# and neither do base packages, which `apk add` alone does not upgrade.
# claude-terminal shipped an out-of-date libexpat (CVE-2026-77214) exactly this
# way. build.yaml passes a value unique to the run on a release only, so every
# release upgrades and reinstalls from the current index; push-to-main and local
# test builds pass nothing and keep their cache. Docker already treats a changed
# ARG as a cache miss at the next RUN; the echo names it there too, and logs
# which refresh a build used.
ARG APK_REFRESH=""
RUN echo "apk refresh: ${APK_REFRESH:-none}" \
    && apk upgrade --no-cache \
    && apk add --no-cache \
    bash=5.3.9-r1 \
    coreutils=9.11-r0 \
    curl=8.23.0-r0 \
    grep=3.12-r0 \
    iproute2=7.0.0-r0 \
    iputils-ping=20250605-r2 \
    lm-sensors=3.6.0-r5 \
    mdadm=4.3-r3 \
    nvme-cli=2.16-r1 \
    procps-ng=4.0.6-r0 \
    smartmontools=7.5-r0 \
    util-linux=2.42.3-r1 \
    wget=1.25.0-r3

COPY rootfs /

# io.hass.version and io.hass.arch are not set here: the Build workflow's
# builder action labels the image with the release tag's version and the arch.
LABEL \
    io.hass.name="HetrixTools Agent" \
    io.hass.description="Runs the HetrixTools server monitoring agent for this HA host" \
    io.hass.type="app" \
    org.opencontainers.image.source="https://github.com/owine/ha-hetrixtools-agent"
