# HetrixTools Agent for Home Assistant

Runs the HetrixTools server monitoring agent on your Home Assistant OS host. The agent reports CPU, RAM, disk, network, and other host metrics to your HetrixTools dashboard. It runs in a privileged container with host visibility, so the metrics reflect the real HA OS host rather than the container.

## Install

1. In Home Assistant, go to **Settings → Apps → app store**.
2. Open the three-dot menu and choose **Repositories**.
3. Add the repository URL: `https://github.com/owine/ha-hetrixtools-agent`
4. Find **HetrixTools Agent** in the app store and install it.
5. Set your 32-character HetrixTools Server ID in the app's Configuration tab, then start the app.

For full setup instructions, option descriptions, and HA OS caveats, see [DOCS.md](DOCS.md).
