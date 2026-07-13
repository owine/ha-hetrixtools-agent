# Home Assistant base image — multi-arch minimal Alpine; buildx selects the arch
# per native-runner build. Pinned to a tag + digest (Renovate keeps the digest
# current). For local testing you can override with a plain tag (no digest), e.g.
#   --build-arg BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24@sha256:94ff231402a5e7ad2a82e261ad5fa4ffae7d7bb095c3febb2edbdf309c9b6aca
FROM ${BUILD_FROM}

# Tools the HetrixTools agent shells out to (host-facing via full_access/udev).
# GNU grep is required: the agent uses `grep -oP … \K` (PCRE) to extract host
# IPv4/IPv6 addresses, which the base image's BusyBox grep cannot do. procps-ng
# likewise supplies the `ps -eo`/`vmstat` BusyBox lacks.
#
# Versions are pinned and kept current by Renovate via the Repology datasource
# (see the customManager in renovate.json). Alpine's index keeps only the newest
# build of each apk and purges the rest, so a drifted pin fails the build rather
# than silently installing something stale — every pin must co-bump in one PR,
# which is what the shared :alpine preset's grouping guarantees. When the base
# image crosses a release line, update the alpine_3_24/ template to match.
RUN apk add --no-cache \
    bash=5.3.9-r1 \
    coreutils=9.11-r0 \
    curl=8.21.0-r0 \
    grep=3.12-r0 \
    iproute2=7.0.0-r0 \
    lm-sensors=3.6.0-r5 \
    mdadm=4.3-r3 \
    nvme-cli=2.16-r1 \
    procps-ng=4.0.6-r0 \
    smartmontools=7.5-r0 \
    util-linux=2.42.1-r0 \
    wget=1.25.0-r3

COPY rootfs /

LABEL \
    io.hass.name="HetrixTools Agent" \
    io.hass.description="Runs the HetrixTools server monitoring agent for this HA host" \
    io.hass.type="addon" \
    org.opencontainers.image.source="https://github.com/owine/ha-hetrixtools-agent"
# x-release-please-start-version
LABEL io.hass.version="0.1.0"
# x-release-please-end
