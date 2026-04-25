# WireTap

> Phone + Mob = WireTap

A universal runtime transparency and test automation layer for native iOS and Android apps,
powered by the BEAM running in-process as a sidecar. The Elixir internals are opaque to
native developers — they see a Swift SDK, a Kotlin SDK, and an MCP server.

**Hex name `wire_tap` is available as of 2026-04-24.**

---

## The problem

Every existing native app test tool is external to the app. They communicate through the
accessibility bridge (XCUITest, Espresso, Appium) or over HTTP (Appium). This means:

- They can only observe what the OS surfaces through accessibility — not model state, not
  in-flight network calls, not the reason a button is disabled
- Touch synthesis happens after the responder chain, so it can't simulate adversarial
  input timing or intercept events before the app sees them
- There is no connection between the running app and the source code — an agent can grep
  files or read the live screen, but not both at the same time with the same tool

WireTap runs inside the app process via the BEAM NIF. It has privileges no external tool has.

---

## What it is

Playwright unified browser automation. WireTap does the same for native mobile apps.

The analogy holds structurally:

| Playwright | WireTap |
|---|---|
| Chrome DevTools Protocol | BEAM distribution + gRPC protocol |
| Browser as the runtime | iOS/Android app as the runtime |
| DOM / accessibility tree | Native view hierarchy + BEAM render tree |
| Page.evaluate() | RPC into the live BEAM process |
| Network interception | Touch event interception (cocoon model) |
| Playwright MCP | WireTap MCP server |
| TypeScript SDK | Swift SDK + Kotlin SDK |

The key difference: Playwright observes what the browser renders. WireTap is inside the
process — it can see model state, intercept the touch stream before it reaches the app,
and read the source code through the MCP server simultaneously.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Agent / AI                              │
│                    WireTap MCP Server                           │
│   read_code · build · run · tap · assert · screenshot · diff   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                     gRPC Protocol                               │
│         bidirectional streaming · protobuf schema               │
└──────────┬───────────────────────────────────────┬──────────────┘
           │                                       │
    ┌──────▼──────┐                         ┌──────▼──────┐
    │  Swift SDK  │                         │ Kotlin SDK  │
    │  (XCTest)  │                         │  (JUnit)    │
    └──────┬──────┘                         └──────┬──────┘
           │                                       │
┌──────────▼───────────────────────────────────────▼──────────────┐
│                    BEAM Core (in-process NIF)                   │
│                                                                 │
│  Erlang distribution  ·  accessibility tree walker              │
│  touch event interception (cocoon model)                        │
│  BEAM render tree (Mob UI apps only)                            │
│  source code reader / project structure parser                  │
│  device API simulation (location, camera, push, etc.)          │
└─────────────────────────────────────────────────────────────────┘
```

The BEAM runs on-device inside the app process. The gRPC server is served from within
that process. Test runners (Xcode Test, JUnit) connect to it via localhost. For CI,
the port is forwarded via `simctl` (iOS) or `adb` (Android).

---

## Two user types

### Native app developers (Swift / Kotlin, no Elixir)

They do not know or care that Elixir is involved. They add a debug-only dependency,
call one function in their app delegate, and gain access to a test SDK that looks
native to their language and test framework.

```swift
// XCTest — Swift
class LoginTests: WireTapTestCase {
    func testLoginFlow() async throws {
        try await app.tap(label: "Sign In")
        try await app.fill("Email", with: "alice@example.com")
        try await app.fill("Password", with: "secret")
        try await app.tap(label: "Submit")
        try await app.assertVisible("Welcome, Alice")
    }
}
```

```kotlin
// JUnit — Kotlin
class LoginTests : WireTapTest() {
    @Test fun loginFlow() = runWireTap {
        app.tap(label = "Sign In")
        app.fill("Email", with = "alice@example.com")
        app.fill("Password", with = "secret")
        app.tap(label = "Submit")
        app.assertVisible("Welcome, Alice")
    }
}
```

### Mob app developers (Elixir)

They get the full apparatus. BEAM state, render tree, component registry, device
simulation, everything. The on-device tests tagged `:on_device` in mob itself are
the Elixir-facing surface of WireTap.

```elixir
use WireTap.Case, node: :"mob_demo_ios@127.0.0.1"

test "counter increments", %{conn: conn} do
  conn
  |> assert_screen(MyApp.CounterScreen)
  |> assert_assigns(count: 0)
  |> tap(tag: :increment)
  |> assert_assigns(count: 1)
  |> assert_visible("Count: 1")    # confirm it actually rendered
end
```

---

## Layers in detail

### 1. Touch event interception (cocoon model)

The BEAM NIF inserts itself into the platform responder chain. It sits above the app —
every touch passes through it before reaching the app's own handlers.

This enables:

- **Recording**: capture an exact touch sequence during development, replay in CI
- **Synthesis**: inject touches that are indistinguishable from real user input
- **Adversarial testing**: inject touches at invalid timing, rapid sequences, conflicting gestures
- **Gating**: let through only touches matching a test scenario; suppress the rest
- **Observation**: watch the full responder chain response, not just accessibility output

This is qualitatively different from UIAutomation synthesis, which happens after the
responder chain and is visible to the OS as synthetic.

### 2. Runtime introspection

Two parallel trees are available simultaneously:

**Native accessibility tree** — what the OS sees. Works for any app, no Mob required.
Available via the NIF's in-process UIAccessibility / AccessibilityNodeInfo walk. Faster
and more reliable than XCUITest (no IPC round-trip).

**BEAM render tree** — what Mob computed. Exact structured data, sub-millisecond reads.
Only available for Mob UI apps. Contains assigns, component registry state, nav stack,
pending events.

Tests can mix both. Assert against BEAM state for exactness; assert against the
accessibility tree to confirm it actually rendered.

### 3. Source code introspection (MCP layer)

The MCP server has access to the project on disk. It understands:

- Xcode project structure (`.xcodeproj`, `Package.swift`, target membership)
- Gradle project structure (modules, flavors, build variants)
- Which files belong to which targets
- The dependency graph

Combined with live runtime state, an agent can answer questions no existing tool can:

> "The submit button is disabled because `isSubmitting` is true, set at
> `LoginViewModel.swift:47` when the request starts and never reset on error."

This requires both the source (what was intended) and the live state (what is
happening). The MCP server holds both simultaneously.

### 4. Device API simulation

All device capabilities can be simulated without hardware:

```swift
// Swift
try await app.simulate(.location(lat: 43.65, lon: -79.38))
try await app.simulate(.notification(title: "Hi", body: "Message"))
try await app.simulate(.permission(.camera, granted: true))
try await app.simulate(.photo(path: "fixtures/test_photo.jpg"))
```

This goes through the BEAM's existing device simulation layer, not OS-level mocks.
It works identically on simulator and real device.

### 5. gRPC protocol

The protocol between the BEAM and the Swift/Kotlin SDKs is defined in protobuf.
The `.proto` schema is the API contract. SDKs are generated, then wrapped in
ergonomic Swift/Kotlin.

Bidirectional streaming handles the event-driven requirements:
- Server-streaming: app state changes, accessibility events, touch events flow to the test runner continuously
- Client-streaming: test runners send command sequences
- Unary: point queries (current tree, current assigns, screenshot)

The schema is the documentation. New BEAM capabilities are available to all SDKs
after regenerating from the updated `.proto`.

---

## Delivery mechanism: inject / eject

For native app developers, integration is a single command and debug-only. Production
builds are unaffected.

```bash
# iOS
wire_tap inject MyApp.xcodeproj

# Android
wire_tap inject app/build.gradle
```

What inject does:
- Adds the BEAM sidecar as a debug-only compile target (iOS) or `debugImplementation` dependency (Android)
- Adds a single `#if DEBUG` / `BuildConfig.DEBUG` call to start the sidecar
- Emits a `.wire_tap.json` config file (node name, port, cookie) for the SDK to auto-discover
- Does not touch any production code paths

```bash
wire_tap eject MyApp.xcodeproj   # git diff shows nothing meaningful
```

`eject` is a clean inverse. This is load-bearing for the trust model — developers can
verify WireTap leaves no production footprint.

---

## MCP server tools

For agents (Claude Code, Cursor, etc.) the MCP server exposes:

| Tool | What it does |
|---|---|
| `wiretap_build` | Build the app (xcodebuild / gradlew) |
| `wiretap_launch` | Launch on simulator / emulator |
| `wiretap_tree` | Get the current accessibility + BEAM render tree |
| `wiretap_tap` | Tap by label, text, accessibility ID, or coordinates |
| `wiretap_type` | Type text into focused field |
| `wiretap_swipe` | Swipe gesture |
| `wiretap_screenshot` | Screenshot |
| `wiretap_assert` | Assert element visible / invisible |
| `wiretap_wait` | Wait for element or condition |
| `wiretap_simulate` | Simulate device API (location, camera, etc.) |
| `wiretap_read_source` | Read source file with project context |
| `wiretap_search_source` | Search across project files |
| `wiretap_assigns` | Get live BEAM assigns (Mob apps only) |
| `wiretap_logs` | Tail app logs |

---

## What to build (rough order)

1. **Protocol definition** — the `.proto` schema. Everything else derives from this.
2. **BEAM gRPC server** — serve from within the app process, handle the lifecycle.
3. **inject / eject** — prerequisite for native developer adoption.
4. **Swift SDK** — codegen from proto + ergonomic wrapper for XCTest.
5. **Kotlin SDK** — codegen from proto + ergonomic wrapper for JUnit.
6. **MCP server** — the agent-facing layer, builds on the same BEAM core.
7. **Touch interception** — the cocoon model. Most technically complex; highest value.
8. **Source introspection** — Xcode / Gradle project parsing for the MCP layer.

Steps 1–3 are the foundation everything else stands on. Steps 7–8 are what make
WireTap categorically different from Appium.

---

## Relation to Mob

WireTap lives beside Mob but is independent of it. Mob UI apps get the full apparatus
(BEAM render tree, assigns, component registry). Native apps get everything except
the Mob-specific layers.

The existing `Mob.Test` module and `:on_device` tagged tests in the Mob test suite
are the Elixir-facing prototype of WireTap. When WireTap ships, Mob's own test
infrastructure will be built on it.

---

*First captured 2026-04-24. Return to this after Mob framework tidying.*
