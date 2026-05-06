# Guides Catalog

Complete classification of documentation guides in the Dala project.

## Quick Navigation by Topic

| Topic | Guides |
|-------|--------|
| **New to Dala?** | [Getting Started](#getting-started), [Architecture](#getting-started), [Build & BEAM Loading](#getting-started) |
| **Building UI** | [Components](#ui--components), [Styling](#ui--components), [Theming](#ui--components), [UI Design](#ui--components) |
| **Navigation** | [Navigation](#ui--components), [Screen Lifecycle](#ui--components) |
| **Events** | [Events](#events--interaction), [Event Model](#events--interaction), [Event Audit](#events--interaction) |
| **Testing** | [Testing](#testing--development), [Agentic Coding](#testing--development) |
| **iOS Development** | [iOS Physical Device](#ios--rust), [iOS ML Support](#ios--rust), [Rustler in Mobile](#ios--rust) |
| **Data & APIs** | [Data & Persistence](#data--device-apis), [Device Capabilities](#data--device-apis) |
| **Advanced** | [LiveView Integration](#advanced-topics), [Publishing](#advanced-topics), [Security](#advanced-topics) |

---

## Getting Started

Guides for newcomers and understanding the system architecture.

### [Getting Started](getting_started.md)
**File**: `guides/getting_started.md`  
**Description**: Step-by-step setup for iOS and Android development, including simulator/emulator setup, physical device deployment, and LiveView projects.

**Key sections**:
- iOS only (simulator + physical device)
- Android only (emulator + physical device)
- Both platforms
- LiveView projects
- After the first deploy
- Toolchain managers

---

### [Architecture & Prior Art](architecture.md)
**File**: `guides/architecture.md`  
**Description**: System architecture, deploy model, Erlang distribution, and how Dala compares to other frameworks.

**Key sections**:
- Deploy model (initial vs subsequent deploys)
- Erlang distribution
- Connection lifecycle
- dala_dev server role

---

### [Build & BEAM Loading](build_and_beam_loading.md)
**File**: `guides/build_and_beam_loading.md` *(new)*  
**Description**: Complete guide on building Dala apps and how the BEAM runtime loads on iOS and Android devices.

**Key sections**:
- iOS build (simulator vs device)
- Android build with NDK
- BEAM loading process (iOS/Android)
- Erlang distribution setup
- Troubleshooting BEAM startup

---

## UI & Components

Guides for building user interfaces with Dala.

### [Components](components.md)
**File**: `guides/components.md`  
**Description**: Detailed reference for all UI components available in Dala, including props, examples, and platform-specific behavior.

**Components covered**: text, button, image, list, column, row, scroll, and more.

---

### [Styling & Native Rendering](styling.md)
**File**: `guides/styling.md`  
**Description**: How to style components, use design tokens, and understand the native rendering pipeline.

---

### [Theming](theming.md)
**File**: `guides/theming.md`  
**Description**: Creating and applying themes, built-in themes (Obsidian, Citrus, Birch), and custom theme creation.

---

### [UI Design](ui_design.md)
**File**: `guides/ui_design.md`  
**Description**: Design patterns, sigil syntax vs Spark DSL, and UI best practices.

---

### [UI Render Pipeline](ui_render_pipeline.md)
**File**: `guides/ui_render_pipeline.md`  
**Description**: End-to-end pipeline from Elixir UI trees to native rendering (Elixir → JSON/Binary → NIF → SwiftUI/Compose).

---

### [Render Engine](render_engine.md)
**File**: `guides/render_engine.md`  
**Description**: Deep dive into the render engine, including the binary protocol, encoding, and performance considerations.

---

### [Binary Protocol](binary_protocol.md)
**File**: `guides/binary_protocol.md`  
**Description**: Specification for the custom binary protocol used between Elixir and native (replaces JSON for better performance).

---

### [Spark DSL](spark_dsl.md)
**File**: `guides/spark_dsl.md`  
**Description**: Declarative DSL for defining screens using Spark. Covers attributes, screen blocks, and compile-time verifiers.

---

### [Screen Lifecycle](screen_lifecycle.md)
**File**: `guides/screen_lifecycle.md`  
**Description**: Understanding screen lifecycle events, mount/cleanup, and navigation integration.

---

### [Navigation](navigation.md)
**File**: `guides/navigation.md`  
**Description**: Navigation patterns, stack navigation, modal presentation, and deep linking.

---

## Events & Interaction

Guides for handling user interaction and events.

### [Events](events.md)
**File**: `guides/events.md`  
**Description**: Event system overview, tap handlers, gestures, and custom events.

---

### [Event Model](event_model.md)
**File**: `guides/event_model.md`  
**Description**: Detailed event model, message passing, and how events flow through the system.

---

### [Event Audit](event_audit.md)
**File**: `guides/event_audit.md`  
**Description**: Tools and techniques for auditing event flow and debugging event-related issues.

---

## Data & Device APIs

Guides for data persistence and accessing device capabilities.

### [Data & Persistence](data.md)
**File**: `guides/data.md`  
**Description**: Data storage options, Ecto integration, and persistence patterns.

---

### [Device Capabilities](device_capabilities.md)
**File**: `guides/device_capabilities.md`  
**Description**: Accessing device features (camera, location, biometrics, etc.) and capability detection.

---

## Testing & Development

Guides for testing, debugging, and development workflows.

### [Testing](testing.md)
**File**: `guides/testing.md`  
**Description**: Testing strategies, `Dala.Test` module, and writing tests for Dala apps.

---

### [Agentic Coding](agentic_coding.md)
**File**: `guides/agentic_coding.md`  
**Description**: How AI agents can work with Dala apps, using `Dala.Test` for inspection, and the three-layer inspection stack.

**Key sections**:
- Priming the agent
- Setting up MCP tools (iOS simulator, ADB)
- The three-layer inspection stack
- Standard agent loop

---

## iOS & Rust

Guides specific to iOS development and Rust NIF integration.

### [iOS Physical Device](ios_physical_device.md)
**File**: `guides/ios_physical_device.md`  
**Description**: Complete guide to building and deploying on physical iOS devices, including provisioning, code signing, and device-specific gotchas.

**Key sections**:
- Build paths (simulator vs device)
- Building OTP from source for iOS
- Bundling OTP in the app
- EPMD as in-process thread
- Static NIF registration
- Pitfalls and troubleshooting

---

### [iOS ML Support](ios_ml_support.md)
**File**: `guides/ios_ml_support.md`  
**Description**: Using Nx, Axon, and EMLX for machine learning on iOS devices.

---

### [EMLX iOS Summary](emlx_ios_summary.md)
**File**: `guides/emlx_ios_summary.md`  
**Description**: Quick reference for EMLX setup on iOS, including JIT limitations and Metal GPU usage.

---

### [Rustler in Mobile](rustler_in_mob.md)
**File**: `guides/rustler_in_mob.md`  
**Description**: Writing Rust NIFs for iOS and Android, platform-specific code, and calling ObjC/Java from Rust.

**Key sections**:
- When to use Rustler in Dala
- Project structure
- Creating NIF functions
- Platform-specific code (iOS/Android)
- Message delivery from native to Elixir

---

### [Rustler Message Sending](rustler_message_sending.md)
**File**: `guides/rustler_message_sending.md`  
**Description**: How to send messages from Rust NIFs back to Elixir, including platform-specific dispatch mechanisms.

---

## Advanced Topics

Advanced guides for specialized use cases.

### [LiveView Integration](liveview.md)
**File**: `guides/liveview.md`  
**Description**: Using Dala with Phoenix LiveView, including setup, configuration, and bridging.

---

### [Publishing to App Store / TestFlight](publishing.md)
**File**: `guides/publishing.md`  
**Description**: Preparing and submitting Dala apps to the iOS App Store and Google Play.

---

### [Security Guide](security.md)
**File**: `guides/security.md`  
**Description**: Security best practices, data protection, and secure coding guidelines for Dala apps.

---

### [Troubleshooting](troubleshooting.md)
**File**: `guides/troubleshooting.md`  
**Description**: Common issues, debugging techniques, and solutions for Dala development problems.

---

## Summary Table

| Category | Count | Guides |
|----------|-------|--------|
| Getting Started | 3 | Getting Started, Architecture, Build & BEAM Loading |
| UI & Components | 9 | Components, Styling, Theming, UI Design, UI Render Pipeline, Render Engine, Binary Protocol, Spark DSL, Screen Lifecycle, Navigation |
| Events & Interaction | 3 | Events, Event Model, Event Audit |
| Data & Device APIs | 2 | Data & Persistence, Device Capabilities |
| Testing & Development | 2 | Testing, Agentic Coding |
| iOS & Rust | 5 | iOS Physical Device, iOS ML Support, EMLX iOS Summary, Rustler in Mobile, Rustler Message Sending |
| Advanced Topics | 4 | LiveView Integration, Publishing, Security, Troubleshooting |
| **Total** | **28** | |

---

## File Naming Convention

All guide files follow the pattern: `guides/{topic}_{specific}.md`

- Topics: `ios_`, `rustler_`, `ui_`, `event_`, etc.
- Words separated by underscores
- Descriptive but concise names

## Contributing New Guides

When adding a new guide:

1. Place it in the `guides/` directory
2. Follow the naming convention
3. Add it to `mix.exs` under `extras:`
4. Assign it to the appropriate `groups_for_extras:` category
5. Update this catalog with the new entry
6. Run `mix format` and `mix credo --strict` before committing
