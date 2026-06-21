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

## HA OS caveats

**Temperatures:** The agent reads hardware temperature sensors via hwmon. Whether temperatures are reported depends on what your specific hardware exposes. On some HA OS devices no temperature sensors are accessible; this is not an error — the metric is simply omitted.

**`check_reboot`:** HA OS does not write a reboot-required flag file, so this option does nothing in practice on most systems.

**`check_services`:** Service checking uses pgrep-style process name matching. It does not query host systemd, so it cannot tell you whether a systemd unit is active — only whether a process with a matching name is running.

**Missing tools:** If a required helper tool (e.g. `smartctl`, `mdadm`) is not present, the corresponding metric is skipped rather than causing a crash.

## Troubleshooting

**No data in HetrixTools after a few minutes:** Check that your `sid` is correct (exactly 32 alphanumeric characters). Enable `dry_run`, restart the app, and check the **Log** tab. You should see the payload that would be sent to HetrixTools. If the payload looks correct, disable `dry_run` and restart again.

**App fails to start:** Check that `sid` matches the 32-character pattern. An invalid SID stops the agent before it sends anything, and because the service is supervised you will see the start failure repeat in the **Log** tab until you correct the SID.

**Metrics are missing or zero:** Some metrics require specific hardware support. If a metric is absent from HetrixTools but you expect it, enable `dry_run` and inspect the log to see what the agent is collecting locally.

## Maintenance and updates

The HetrixTools agent binary is vendored inside this app at v2.4.1. It does not self-update. When HetrixTools releases a new agent version, a Renovate PR will be opened on the repository bumping `hetrixtools-agent/upstream-agent.version`. That PR is the signal to re-vendor the agent and re-apply the small `dry_run` patch (look for `>>> ha-app patch >>>` markers in `hetrixtools_agent.sh`). App updates are then delivered through the normal HA app update flow.
