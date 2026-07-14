# MasterFabric Mac CLI

> **Open source.** MacBook system monitor with a first-class **MCP** server — so Cursor, Claude, and any agent can read CPU/GPU temps, fans, battery, and more on your machine.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black.svg)](https://github.com/gurkanfikretgunak/masterfabric-mac-cli)
[![MCP](https://img.shields.io/badge/MCP-stdio%20ready-6E56CF.svg)](https://github.com/gurkanfikretgunak/masterfabric-mac-cli#mcp--agent-ready)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg)](Package.swift)

**Repo:** [github.com/gurkanfikretgunak/masterfabric-mac-cli](https://github.com/gurkanfikretgunak/masterfabric-mac-cli)

Native Swift · Apple Silicon first · **No telemetry** · MIT

---

## Why MasterFabric?

| Surface | What you get |
|--------|----------------|
| **MCP** | AI agents call `get_status`, `get_battery`, `get_cpu_load`, … over stdio |
| **CLI (`mf`)** | Scriptable metrics with `--json` |
| **Menu Bar** | Always-on CPU °C · load · fan in the macOS status bar |

Built for developers who want local hardware context inside their coding agents — not another closed menu-bar utility.

---

## MCP — agent-ready

MasterFabric speaks **Model Context Protocol** out of the box. Point Cursor or Claude Desktop at one binary:

```bash
mf mcp
```

**Cursor** — add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "masterfabric": {
      "command": "/Users/YOU/.local/bin/mf",
      "args": ["mcp"]
    }
  }
}
```

Copy-paste starter: [examples/mcp.json](examples/mcp.json)

### Tools agents can call

| Tool | Returns |
|------|---------|
| `get_status` | CPU/GPU °C + fan RPM |
| `get_temp` / `get_fan` | Temps or fans only |
| `get_info` | Model, chip, macOS, RAM, uptime |
| `get_battery` | %, health, cycles, watts |
| `get_memory` / `get_disk` / `get_network` | Host metrics |
| `get_cpu_load` | Overall + per-core % |
| `get_power` | Thermal state, Low Power Mode |
| `get_top` / `get_history` | Hot processes + 1h sparklines |
| `set_alert_threshold` | Update `config.toml` alerts |
| `get_about` | Version + privacy |

**Resource:** `masterfabric://status` — live JSON snapshot.

> Your sensors never leave the Mac. MCP is **local stdio** only — no cloud relay.

---

## Install (CLI)

**One-liner:**

```bash
curl -fsSL https://raw.githubusercontent.com/gurkanfikretgunak/masterfabric-mac-cli/main/scripts/install.sh | bash
```

**From source:**

```bash
git clone https://github.com/gurkanfikretgunak/masterfabric-mac-cli.git
cd masterfabric-mac-cli
make install
export PATH="$HOME/.local/bin:$PATH"
```

**Verify:**

```bash
mf --version
mf status
mf menubar
```

Requires macOS 13+ and Swift (Xcode or CLT). Apple Silicon recommended.

Homebrew formula (tap after tagging a release): [`Formula/masterfabric.rb`](Formula/masterfabric.rb)

---

## Menu Bar

Live status item (English UI): **CPU °C · load% · Fan RPM**. Click for model, GPU, battery, memory, thermal state, CPU history, **Alerts** (circle icon thresholds), and **Integrations** with official-color brand badges.

![MasterFabric menu bar](docs/screenshots/menubar.png)

```bash
mf menubar          # launch
mf login enable     # start at login
```

App bundle: `~/.local/MasterFabricMenuBar.app` (no Dock icon).

- **Alerts** — tap thermometer / GPU / fan / memory / disk / battery / power icons to edit thresholds; optional **Send to Integrations**
- **Integrations** — Slack · Telegram · Mail with on/off toggles, Edit, and circle brand badges (configure without the terminal via **+**)

---

## CLI

Scriptable metrics with `--json`. Example session:

![MasterFabric CLI](docs/screenshots/cli.png)

```bash
mf status
mf cpu
mf memory
mf notify status
mf bot --help
mf about
```

### Cheat sheet

```text
mf status | temp | fan | info
mf battery | memory | disk | network | cpu
mf power | top | history | watch
mf check [--notify]
mf notify status | test | send --channel slack "hello"
mf bot telegram
mf config show | init | set <key> <value>
mf login enable | disable | status
mf about [--lang en|tr]
mf menubar
mf mcp
```

All read commands support `--json`.

---

## Integrations — Slack · Telegram · Mail

Push alerts (or any message) to chat/email from the CLI or MCP.

```bash
mf config init
mf config set integrations.slack.enabled true
mf config set integrations.slack.webhook_url "https://hooks.slack.com/services/…"

mf config set integrations.telegram.enabled true
mf config set integrations.telegram.bot_token "123:ABC"
mf config set integrations.telegram.chat_id "987654321"

mf config set integrations.mail.enabled true
mf config set integrations.mail.provider resend   # or smtp | mailgun
mf config set integrations.mail.from "alerts@example.com"
mf config set integrations.mail.to "you@example.com"
mf config set integrations.mail.api_key "re_xxx"

mf notify test --channel all
mf check --notify
mf notify send --channel slack "CPU spike on build machine"
```

Full sample: [examples/integrations.toml](examples/integrations.toml)

| Channel | Config |
|---------|--------|
| **Slack** | Incoming webhook URL |
| **Telegram** | Bot token + chat id |
| **Mail** | `resend` / `mailgun` API key, or `smtp` (via `python3` smtplib) |

MCP tools: `notify_send`, `notify_status`.

### Telegram interactive bot (Q&A)

Keep a process running on the Mac so the bot can answer questions with live metrics:

```bash
mf bot telegram
```

Then in Telegram:

```text
/status
/temp
/fan
/battery
how's the fan?
cpu load?
```

Only the configured numeric `chat_id` is allowed. Ctrl+C stops the listener.

---

## Config & privacy

`~/.config/masterfabric/config.toml` — language, poll interval, alert thresholds, launch-at-login.

```bash
mf config init
mf config set alerts.cpu_temp_celsius 88
```

**Privacy-first:** readings stay on-device. No analytics, no accounts, no network calls for core monitoring.

---

## Open source

- **License:** [MIT](LICENSE)
- **Issues / PRs:** welcome at [gurkanfikretgunak/masterfabric-mac-cli](https://github.com/gurkanfikretgunak/masterfabric-mac-cli)
- **Stack:** SwiftPM · IOKit/SMC · SwiftUI `MenuBarExtra` · MCP JSON-RPC stdio

```bash
swift build
swift run mf status
make install
```

---

## License

MIT © MasterFabric contributors
