# Dala Guides

Quick reference for all Dala documentation. Files are in `dala/guides/`.

## Orientation

| Guide | Description |
|-------|-------------|
| [agentic_coding.md](agentic_coding.md) | AI agent workflow: Dala.Test, MCP tools, round-trip loop |
| [why_beam.md](why_beam.md) | BEAM-on-mobile pitch: concurrency, hot-code, distribution |
| [getting_started.md](getting_started.md) | First app setup, REPL, basic screen |

## Architecture

| Guide | Description |
|-------|-------------|
| [architecture.md](architecture.md) | System overview, native cocoon model |
| [render_engine.md](render_engine.md) | Elixir → JSON → NIF → SwiftUI/Compose pipeline |
| [event_model.md](event_model.md) | Event envelope, addressing, routing, targets |
| [event_audit.md](event_audit.md) | Event props audit: tap, swipe, long-press, etc. |
| [screen_lifecycle.md](screen_lifecycle.md) | Screen start, stop, navigation lifecycle |

## UI & Design

| Guide | Description |
|-------|-------------|
| [ui_design.md](ui_design.md) | Sigil vs Spark DSL comparison, patterns |
| [spark_dsl.md](spark_dsl.md) | Spark DSL deep dive: attributes, @ref, handlers |
| [components.md](components.md) | Sigil syntax, component reference |
| [theming.md](theming.md) | Colors, spacing, typography tokens |
| [styling.md](styling.md) | `Dala.Style` usage, reusable styles |
| [navigation.md](navigation.md) | Stack navigation, push/pop/reset |

## Data & Persistence

| Guide | Description |
|-------|-------------|
| [data.md](data.md) | `Dala.State` (dets) + Ecto/SQLite layers |
| [events.md](events.md) | Event system and message passing |

## Platform-Specific

| Guide | Description |
|-------|-------------|
| [ios_physical_device.md](ios_physical_device.md) | Provisioning, build chain, gotchas |
| [ios_ml_support.md](ios_ml_support.md) | Nx, Axon, EMLX on iOS |
| [emlx_ios_summary.md](emlx_ios_summary.md) | EMLX setup summary |
| [device_capabilities.md](device_capabilities.md) | Detecting platform features |

## Native & NIF

| Guide | Description |
|-------|-------------|
| [rustler_in_mob.md](rustler_in_mob.md) | Extending Dala with Rust NIFs |
| [rustler_message_sending.md](rustler_message_sending.md) | Message sending from native callbacks |

## Deployment & Operations

| Guide | Description |
|-------|-------------|
| [publishing.md](publishing.md) | App Store / TestFlight (links to dala_dev detailed guide) |
| [testing.md](testing.md) | `Dala.Test` module, writing tests |
| [security.md](security.md) | Security considerations |
| [troubleshooting.md](troubleshooting.md) | Common issues, AGENTS.md pre-empt rules |
| [liveview.md](liveview.md) | Phoenix LiveView wrapper mode |

## Cross-Repo Docs

- **dala_dev guides** — build, deploy, devices: see `dala_dev/CLAUDE.md`
- **dala_new templates** — project generator: see `dala_new/CLAUDE.md`
- **AGENTS.md** — orientation for all repos: `dala/AGENTS.md`, `dala_dev/AGENTS.md`, `dala_new/AGENTS.md`
