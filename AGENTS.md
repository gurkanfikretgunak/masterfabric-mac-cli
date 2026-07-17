# AGENTS.md — MasterFabric Mac CLI

Guidance for AI agents and contributors working in this repository.

## What this project is

Native **Swift / SPM** macOS toolkit (macOS 13+):

| Product | Role |
|---------|------|
| `mf` | CLI + **MCP** stdio server (`mf mcp`) |
| `MasterFabricMenuBar` | Menu bar app (`mf menubar`) |
| `MasterFabricCore` | Shared metrics, config, integrations, version |
| `GenerateScreenshot` | Marketing / docs screenshot helper |

Sensors and config stay **on-device**. No telemetry. Experimental OSS (MIT).

## Layout

```
Sources/MasterFabricCore/   # IOKit/SMC, battery, fan, alerts, config.toml
Sources/mf/                 # ArgumentParser CLI + MCPServer
Sources/MasterFabricMenuBar/# SwiftUI MenuBarExtra (.window)
scripts/install.sh          # One-line installer (clone + make install)
Formula/masterfabric.rb     # Homebrew formula (tag URL)
VERSION                     # Semver source of truth → make version-sync
.cursor/rules/              # Cursor project rules (see below)
```

User config: `~/.config/masterfabric/config.toml`  
Install prefix default: `~/.local` (`mf`, `MasterFabricMenuBar`, `.app`)

## Build & install

```bash
make version-sync          # sync VERSION → Sources/MasterFabricCore/Version.swift
make build                 # debug
make release               # release both products
make install               # release + install to ~/.local + ad-hoc codesign
swift build -c release --product mf
swift build -c release --product MasterFabricMenuBar
```

After install: ensure `~/.local/bin` is on `PATH`. Prefer `make install` over copying unsigned binaries (Tahoe+ may SIGKILL unsigned apps).

**CLT-only machines** (no Xcode.app): SwiftUI `@State` macros may be missing — see `.cursor/rules/menubar-swiftui.mdc`. Prefer `@StateObject` + small `ObservableObject` helpers for local form state.

## Agent workflow

1. Read relevant `.cursor/rules/*.mdc` for the area you touch.
2. Prefer a `feat/…` or `fix/…` branch and an **English** PR (Summary + Test plan).
3. Do **not** bump `VERSION` or publish a GitHub release unless the user explicitly asks — see `release-workflow.mdc`.
4. Never commit secrets, tokens, webhooks, or personal `chat_id` values.
5. Keep PRs and commit messages in **English** even if chat is in another language.

## Cursor rules index

| Rule | When |
|------|------|
| `release-workflow.mdc` | Always — ask before version/release |
| `project-core.mdc` | Always — architecture & privacy |
| `security-privacy.mdc` | Always — secrets & local-only data |
| `build-install.mdc` | Always — make/SPM/install/codesign |
| `swift-conventions.mdc` | `Sources/**/*.swift` |
| `menubar-swiftui.mdc` | `Sources/MasterFabricMenuBar/**` |
| `mcp-cli.mdc` | `Sources/mf/**` |

## Quick verify

```bash
mf version
mf status --json
mf menubar
# MCP: mf mcp  (stdio JSON-RPC)
```
