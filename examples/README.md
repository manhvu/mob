# Dala Examples

Ready-to-run example applications demonstrating Dala framework features.

## Quick Start

All examples are **zero-config** - just run them!

### Prerequisites

- Elixir installed
- For iOS: Xcode with iOS Simulator
- For Android: Android Studio with emulator

---

## 1. Simple App (`simple_app/`)

Basic Dala app with navigation and state management.

### Features:
- Counter with increment button
- Navigation between screens
- Back button functionality
- No configuration needed!

### Run it:

```bash
cd examples/simple_app
mix deps.get
mix dala.deploy --native --ios-sim    # iOS Simulator
# or
mix dala.deploy --native --android-emu  # Android Emulator
```

---

## 2. ML App (`ml_app/`)

On-device machine learning with YOLO object detection.

### Features:
- **Zero configuration** - EMLX auto-setups for iOS/Android
- YOLO object detection (simulated)
- Camera integration ready
- Metal GPU acceleration on Apple Silicon
- Falls back to CPU on non-GPU platforms

### Run it:

```bash
cd examples/ml_app
mix deps.get

# iOS (requires EMLX dependencies - auto-downloaded):
mix dala.deploy --native --ios-sim

# Android:
mix dala.deploy --native --android-emu
```

### What it does:

1. **Auto-configures ML backend** - No manual setup needed!
   - iOS device: EMLX with Metal GPU, JIT disabled (W^X policy)
   - iOS Simulator: EMLX with Metal GPU, JIT enabled
   - Other platforms: Pure Nx (CPU)

2. **Simulates YOLO detection** - Tap "Run YOLO Detection" to see sample results

3. **Camera ready** - Tap "Open Camera" for live detection (integration point)

### ML Dependencies (automatically included):

- `:nx` - Tensor library (pure Elixir)
- `:emlx` - MLX backend for Apple Silicon
- `:axon` - Neural network library

These are automatically added in `mix.exs` - no work for you!

---

## How It Works (Zero Config Magic)

### Simple App:

```elixir
# examples/simple_app/lib/simple_app.ex
def on_start do
  # Pattern-match ensures failures crash loudly (AGENTS.md Rule #2)
  {:ok, _pid} = Dala.Screen.start_root(SimpleApp.HomeScreen)
  :ok
end
```

### ML App:

```elixir
# examples/ml_app/lib/ml_app.ex
def on_start do
  # Auto-configure ML backend - that's it!
  case Dala.ML.EMLX.setup() do
    {:ok, config} ->
      :dala_nif.log("MLApp: EMLX configured - device: #{config.device}")
    :ok ->
      :dala_nif.log("MLApp: Using default Nx backend (non-iOS)")
  end

  {:ok, _pid} = Dala.Screen.start_root(MLApp.HomeScreen)
  :ok
end
```

The `Dala.ML.EMLX.setup/0` function:
- Detects iOS device vs simulator
- Disables JIT on real devices (required by W^X policy)
- Enables Metal GPU on Apple Silicon
- Sets EMLX as default Nx backend
- Safe to call on non-iOS platforms (becomes no-op)

---

## Next Steps

- Read the [Dala Documentation](https://hexdocs.pm/dala)
- Check out the [guides/](../../guides/) folder
- Join the community discussions

---

## Troubleshooting

### "mix: command not found"
Install Elixir: https://elixir-lang.org/install.html

### iOS deploy fails
Make sure Xcode is installed and you have an iOS Simulator running.

### Android deploy fails
Make sure Android Studio is installed and you have an emulator created.

### ML features not working
EMLX requires iOS/Android with GPU support. On other platforms, the app falls back to CPU-based Nx (still works, just slower).
