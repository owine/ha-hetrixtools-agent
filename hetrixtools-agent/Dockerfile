# Home Assistant base image — multi-arch minimal Alpine; buildx selects the arch
# per native-runner build. Pinned tag + digest; Renovate keeps the digest fresh.
# For local testing, override with --build-arg BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24@sha256:94ff231402a5e7ad2a82e261ad5fa4ffae7d7bb095c3febb2edbdf309c9b6aca
FROM ${BUILD_FROM}

# Tools the HetrixTools agent shells out to (host-facing via full_access/udev).
# GNU grep is required: the agent uses `grep -oP … \K` (PCRE) to extract host
# IPv4/IPv6 addresses, which the base image's BusyBox grep cannot do.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    coreutils \
    grep \
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
    org.opencontainers.image.source="https://github.com/owine/ha-hetrixtools-agent"
# x-release-please-start-version
LABEL io.hass.version="0.1.0"
# x-release-please-end
