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
