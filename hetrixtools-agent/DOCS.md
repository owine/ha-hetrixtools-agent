# HetrixTools Agent

## What it does

This app runs the HetrixTools server monitoring agent (v2.4.1) inside a privileged container with full access to the HA OS host. Because it uses `host_pid`, `host_network`, and `full_access`, the agent reports metrics from the real host rather than the container:

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
6. Start the app.

After the first data collection cycle, give HetrixTools up to about two minutes to display the initial metrics.

## Configuration options

| Option | Type | Default | Description |
|---|---|---|---|
| `sid` | string | *(required)* | Your 32-character HetrixTools Server ID. |
| `collect_every_seconds` | integer (1–60) | `3` | How often the agent collects and sends metrics, in seconds. |
| `check_drive_health` | boolean | `false` | Enable SMART drive health checks. Requires drives that support SMART. |
| `check_soft_raid` | boolean | `false` | Enable software RAID (md) status checks. |
| `check_reboot` | boolean | `false` | Check whether the host needs a reboot. On HA OS this is usually a no-op because the reboot-required file is not written. |
| `running_processes` | boolean | `false` | Report a list of running processes to HetrixTools. |
| `connection_ports` | list of strings | `[]` | Ports to check for active connections (e.g. `["80", "443"]`). |
| `check_services` | list of strings | `[]` | Service names to check. Uses pgrep-style process name matching, not host systemd. |
| `dry_run` | boolean | `false` | Print collected payloads to the app log instead of sending them to HetrixTools. Useful for debugging. |
| `ignored_disks` | string | *(see below)* | Extended-regex of `df` lines to exclude from disk reporting. Empty uses the default `tmpfs|aufs|squashfs|container_tmp|^overlay`. |
| `debug` | boolean | `false` | Echo the agent's internal diagnostics to the app log after each cycle. Verbose; enable only while investigating. |

## HA OS caveats

**Temperatures:** The agent reads hardware temperature sensors via hwmon. Whether temperatures are reported depends on what your specific hardware exposes. On some HA OS devices no temperature sensors are accessible; this is not an error — the metric is simply omitted.

**`check_reboot`:** HA OS does not write a reboot-required flag file, so this option does nothing in practice on most systems.

**`check_services`:** Service checking uses pgrep-style process name matching. It does not query host systemd, so it cannot tell you whether a systemd unit is active — only whether a process with a matching name is running.

**Network interfaces:** The app reports only real host NICs. Home Assistant runs its add-ons under Docker, which creates and destroys `veth*` interfaces constantly; left to its own devices the agent detects interfaces once per cycle and then samples that list for the following minute, so container interfaces that disappear mid-cycle both corrupt the per-NIC traffic figures and fill the log with `awk` syntax errors. The app therefore detects the host's own interfaces at startup and passes them to the agent explicitly, excluding `veth*`, `br-*`, `docker*`, `hassio` and `virbr*`. The interfaces chosen are printed in the **Log** tab when the app starts. Because detection happens at startup, a NIC added to the host later is picked up on the next restart.

**Disk reporting:** Add-ons run under Docker's overlay2 storage driver, so the container's own root filesystem appears in `df` as an `overlay` mount. The default `ignored_disks` filter excludes it, along with the filesystem types the agent already skips, so only real host storage is reported. If you override the option, carry the defaults forward — the value replaces the filter rather than adding to it. The pattern is matched against whole `df` lines, which is why `^overlay` is anchored: an unanchored term would also drop a genuine disk mounted at a path containing that word. An invalid regex disables filtering entirely rather than failing the app.

**Missing tools:** If a required helper tool (e.g. `smartctl`, `mdadm`) is not present, the corresponding metric is skipped rather than causing a crash.

## Troubleshooting

**No data in HetrixTools after a few minutes:** Check that your `sid` is correct (exactly 32 alphanumeric characters). Enable `dry_run`, restart the app, and check the **Log** tab. You should see the payload that would be sent to HetrixTools. If the payload looks correct, disable `dry_run` and restart again.

**App fails to start:** Check that `sid` matches the 32-character pattern. An invalid SID stops the agent before it sends anything, and because the service is supervised you will see the start failure repeat in the **Log** tab until you correct the SID.

**Network traffic looks wrong, or the log is full of `awk` errors:** Older versions let the agent auto-detect interfaces and so included Docker's `veth*` pairs. Restart the app and check the **Log** tab for the `Monitoring network interfaces:` line — it should list your host NIC (commonly `end0` or `eth0`), not `veth*` entries. If it instead warns that no interfaces were detected, the agent falls back to its own auto-detection and the old behaviour returns; please open an issue with your `ip a` output.

**Disks you do not recognise, or a missing disk:** Check `ignored_disks`. An empty value means the default filter; a custom value replaces it outright, so a disk you expect may simply be matched by your own pattern, and one you do not expect may be the container overlay reappearing because the default was overridden without carrying `^overlay` forward.

**Metrics are missing or zero:** Some metrics require specific hardware support. If a metric is absent from HetrixTools but you expect it, enable `dry_run` and inspect the log to see what the agent is collecting locally.

## Maintenance and updates

The HetrixTools agent binary is vendored inside this app at v2.4.1. It does not self-update. When HetrixTools releases a new agent version, a Renovate PR will be opened on the repository bumping `hetrixtools-agent/upstream-agent.version`. That PR is the signal to re-vendor the agent and re-apply the small `dry_run` patch (look for `>>> ha-app patch >>>` markers in `hetrixtools_agent.sh`). App updates are then delivered through the normal HA app update flow.
