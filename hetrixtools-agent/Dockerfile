ARG BUILD_FROM
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
