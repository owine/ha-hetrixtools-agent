# HetrixTools Agent

## What it does

This app runs the HetrixTools server monitoring agent (v2.4.1) inside a container with access to the HA OS host. Because it uses the host network and, with protection mode off, full hardware access, the agent reports metrics from the real host rather than the container:

- CPU usage and load averages
- RAM and swap
- System uptime
- Disk usage (all mounted filesystems)
- SMART drive health (optional)
- Software RAID status (optional)
- Network interface statistics and IP addresses
- Hardware temperatures (where the host exposes hwmon sensors)

These metrics appear in your HetrixTools dashboard under the server monitor you created.

## Prerequisites

- A [HetrixTools](https://hetrixtools.com) account with at least one Uptime Monitor configured as a server monitor
- A Server ID (SID) from HetrixTools — see below

IPMI is not supported; that is normal for HA OS hardware.

## Getting a Server ID

1. Log in to HetrixTools and open your server monitor (or create one under **Uptime Monitors**).
2. Click **Install Monitoring Agent**.
3. Copy the **32-character Server ID** shown in the install command. It looks like `a1b2c3d4e5f6...` — 32 alphanumeric characters.

That SID is what you paste into the app's `sid` option. Each HetrixTools monitor has one SID. If you run this app on multiple HA hosts, create a separate monitor and use a separate SID on each host.

## Installation

1. In Home Assistant, go to **Settings → Apps → app store** (the shopping bag icon in the top right).
2. Click the three-dot menu and choose **Repositories**.
3. Add `https://github.com/owine/ha-hetrixtools-agent` and click **Add**.
4. Find **HetrixTools Agent** in the app store and install it.
5. Before starting the app, open its **Configuration** tab and set your `sid`.
6. If you want SMART drive health, turn **Protection mode** off on the app's **Info** tab (see below).
7. Start the app.

After the first data collection cycle, give HetrixTools up to about two minutes to display the initial metrics.

## Protection mode and privileges

Home Assistant runs every app with **Protection mode** on by default. This app works either way, but reports more with it off.

**With protection mode on**, the app gets the host network and the `NET_RAW` capability. That covers CPU, RAM, swap, load, uptime, disk usage, network traffic, temperatures, software RAID status, and ICMP outgoing pings.

**With protection mode off**, the Supervisor also grants `full_access`, which gives the app every host device and capability. SMART drive health (`check_drive_health`) needs this: `smartctl` has to open the disks directly. Home Assistant shows a warning when protection mode is off, and the app's security rating is 1, because an app with full access can do almost anything to the system. Turn it off only if you want drive health reporting.

The app asks for these privileges for these reasons:

- **Host network:** to see and report the host's real network interfaces and addresses, and to send outgoing pings from the host.
- **`NET_RAW`:** ICMP pings open raw sockets. TCP outgoing pings (`name,host,port`) do not need it.
- **`full_access`:** SMART drive health, as above.
- **`udev`:** read-only access to the host's device database, so drive tools can identify disks.

The app does not use the host's process namespace (`host_pid`). The init system of the Home Assistant base image refuses to start inside it, and CPU, memory and uptime are host-wide without it. The cost is that `running_processes` and `check_services` only see the app's own processes.

## Configuration options

| Option | Type | Default | Description |
|---|---|---|---|
| `sid` | string | *(required)* | Your 32-character HetrixTools Server ID. |
| `collect_every_seconds` | integer (1–60) | `3` | Seconds between samples within each one-minute cycle. Metrics are still sent to HetrixTools once a minute. |
| `check_drive_health` | boolean | `false` | Enable SMART drive health checks. Requires protection mode off and drives that support SMART. |
| `check_soft_raid` | boolean | `false` | Enable software RAID (md) status checks. |
| `check_reboot` | boolean | `false` | Check whether the host needs a reboot. On HA OS this is usually a no-op because the reboot-required file is not written. |
| `running_processes` | boolean | `false` | Report a list of running processes to HetrixTools. Only the app's own processes are visible. |
| `connection_ports` | list of strings | `[]` | Ports to check for active connections (e.g. `["80", "443"]`). |
| `check_services` | list of strings | `[]` | Service names to check. Uses pgrep-style process name matching, and only sees the app's own processes. |
| `dry_run` | boolean | `false` | Print collected payloads to the app log instead of sending them to HetrixTools. Useful for debugging. |
| `ignored_disks` | string | *(see below)* | Extended-regex of `df` lines to exclude from disk reporting. Empty uses the default `tmpfs|aufs|squashfs|container_tmp|^overlay`. |
| `debug` | boolean | `false` | Echo the agent's internal diagnostics to the app log after each cycle. Verbose; enable only while investigating. |
| `outgoing_pings` | list of strings | `[]` | Latency targets, each `name,host` or `name,host,port`. With a port the agent runs a TCP probe instead of ICMP. |
| `outgoing_pings_count` | integer (10–40) | `20` | Probes sent per target per cycle. |

## HA OS caveats

**Temperatures:** The agent reads hardware temperature sensors via hwmon. Whether temperatures are reported depends on what your specific hardware exposes. On some HA OS devices no temperature sensors are accessible; this is not an error — the metric is simply omitted.

**`check_reboot`:** HA OS does not write a reboot-required flag file, so this option does nothing in practice on most systems.

**`check_services` and `running_processes`:** The app runs in its own process namespace (see [Protection mode and privileges](#protection-mode-and-privileges)), so both only see the app's own processes, not Home Assistant, other apps, or host services. Service checking also uses pgrep-style name matching rather than systemd, so it could not tell you whether a systemd unit is active in any case.

**Network interfaces:** The app reports only real host NICs. Home Assistant runs its add-ons under Docker, which creates and destroys `veth*` interfaces constantly; left to its own devices the agent detects interfaces once per cycle and then samples that list for the following minute, so container interfaces that disappear mid-cycle both corrupt the per-NIC traffic figures and fill the log with `awk` syntax errors. The app therefore detects the host's own interfaces at startup and passes them to the agent explicitly, excluding `veth*`, `br-*`, `docker*`, `hassio` and `virbr*`. The interfaces chosen are printed in the **Log** tab when the app starts. Because detection happens at startup, a NIC added to the host later is picked up on the next restart.

**Disk reporting:** Add-ons run under Docker's overlay2 storage driver, so the container's own root filesystem appears in `df` as an `overlay` mount. The default `ignored_disks` filter excludes it, along with the filesystem types the agent already skips, so only real host storage is reported. If you override the option, carry the defaults forward — the value replaces the filter rather than adding to it. The pattern is matched against whole `df` lines, which is why `^overlay` is anchored: an unanchored term would also drop a genuine disk mounted at a path containing that word. An invalid regex disables filtering entirely rather than failing the app.

**Outgoing pings:** Each entry is `name,host` (ICMP) or `name,host,port` (TCP connect probe). `name` may contain letters, digits, `.`, `_` and `-`; `host` may be a hostname or an IP. For example, `["gateway,192.168.1.1", "dns,1.1.1.1", "api,example.com,443"]`. Targets are probed once per cycle and reported to HetrixTools as packet loss and average latency. ICMP probes open raw sockets, which is what the app's `NET_RAW` capability is for; if a target shows total loss but is reachable from the host, try the TCP form with a port.

**Missing tools:** If a required helper tool (e.g. `smartctl`, `mdadm`) is not present, the corresponding metric is skipped rather than causing a crash.

## Troubleshooting

**No data in HetrixTools after a few minutes:** Check that your `sid` is correct (exactly 32 alphanumeric characters). Enable `dry_run`, restart the app, and check the **Log** tab. You should see the payload that would be sent to HetrixTools. If the payload looks correct, disable `dry_run` and restart again.

**App fails to start:** Check that `sid` matches the 32-character pattern. An invalid SID stops the agent before it sends anything, and because the service is supervised you will see the start failure repeat in the **Log** tab until you correct the SID.

**Network traffic looks wrong, or the log is full of `awk` errors:** Older versions let the agent auto-detect interfaces and so included Docker's `veth*` pairs. Restart the app and check the **Log** tab for the `Monitoring network interfaces:` line — it should list your host NIC (commonly `end0` or `eth0`), not `veth*` entries. If it instead warns that no interfaces were detected, the agent falls back to its own auto-detection and the old behaviour returns; please open an issue with your `ip a` output.

**Disks you do not recognise, or a missing disk:** Check `ignored_disks`. An empty value means the default filter; a custom value replaces it outright, so a disk you expect may simply be matched by your own pattern, and one you do not expect may be the container overlay reappearing because the default was overridden without carrying `^overlay` forward.

**No drive health data:** SMART checks need protection mode off. With it on, the app cannot open the disks and the agent skips the metric.

**Outgoing ICMP pings show total loss:** If the target answers pings from the host, check the log for `Operation not permitted`, which means the app was started without the `NET_RAW` capability. Use the TCP form (`name,host,port`) instead.

**Metrics are missing or zero:** Some metrics require specific hardware support. If a metric is absent from HetrixTools but you expect it, enable `dry_run` and inspect the log to see what the agent is collecting locally.

## Maintenance and updates

The HetrixTools agent binary is vendored inside this app at v2.4.1. It does not self-update. When HetrixTools releases a new agent version, a Renovate PR will be opened on the repository bumping `hetrixtools-agent/upstream-agent.version`. That PR is the signal to re-vendor the agent and re-apply the small `dry_run` patch (look for `>>> ha-app patch >>>` markers in `hetrixtools_agent.sh`). App updates are then delivered through the normal HA app update flow.

## Support

Report bugs and ask questions in the [GitHub issue tracker](https://github.com/owine/ha-hetrixtools-agent/issues). Include the app's **Log** tab output, ideally with `debug` on. For problems with the HetrixTools service itself, contact HetrixTools.
