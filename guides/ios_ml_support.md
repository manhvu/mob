# iOS ML Support Guide

This guide covers adding machine learning capabilities to Dala apps on iOS using the Nx ecosystem.

## Overview

For iOS development, only these libraries are supported:

| Component | Status | Notes |
|-----------|--------|-------|
| **Nx** | ✅ Ready | Pure Elixir, works on any platform |
| **Axon** | ✅ Ready | Neural networks, pure Elixir |
| **EMLX** | ⚠️ Setup needed | MLX backend - **recommended for iOS** |

**Not supported on iOS:** Emily (macOS-only), NxIREE, EXLA/XLA, Torchx.



## Quick Start

### 1. Add Dependencies

In your Dala app's `mix.exs`:

```elixir
def deps do
  [
    {:nx, github: "elixir-nx/nx", sparse: "nx"},
    {:axon, "~> 0.6"},
    {:emlx, github: "elixir-nx/emlx", branch: "main"}
  ]
end
```

### 2. Configure for iOS

Create or update `config/config.exs`:

```elixir
# Disable JIT for iOS devices (W^X policy)
config :emlx, :jit_enabled, false

# Use Metal GPU on iOS (unified memory architecture)
config :nx, :default_backend, {EMLX.Backend, device: :gpu}

# Or use CPU backend:
# config :nx, :default_backend, {EMLX.Backend, device: :cpu}
```

### 3. Initialize in Your App

#### Zero-config approach (recommended)

`Dala.ML.EMLX.setup/0` auto-configures EMLX for the platform — no manual `config` needed:

```elixir
defmodule MyApp.App do
  use Dala.App

  def start(_type, _args) do
    # Auto-configures based on platform:
    # - iOS device: Metal GPU, JIT disabled (W^X policy)
    # - iOS simulator: Metal GPU, JIT enabled
    # - Non-iOS: no-op, falls back to Nx.BinaryBackend
    Dala.ML.EMLX.setup()

    # ... rest of your app startup
  end
end
```

This is the **recommended approach** — no manual `config :nx, ...` or `config :emlx, ...` needed!

#### Manual configuration (advanced)

If you need custom settings, initialize manually:

```elixir
defmodule MyApp.App do
  use Dala.App

  def start(_type, _args) do
    # Initialize ML backend for iOS
    Dala.ML.Nx.init_for_ios()

    # ... rest of your app startup
  end
end
```

## EMLX on iOS

### Zero-Config Auto-Configuration

`Dala.ML.EMLX.setup/0` handles all platform-specific configuration automatically:

| Platform | GPU | JIT | Notes |
|----------|-----|-----|-------|
| iOS device | Metal (`:gpu`) | Disabled | W^X policy blocks JIT |
| iOS simulator | Metal (`:gpu`) | Enabled | Shares Mac's network stack |
| Non-iOS | Nx.BinaryBackend | N/A | Falls back to pure Elixir |

Call it once at app startup — no other config needed.

### Key Considerations

1. **JIT Compilation**: iOS devices enforce W^X (Write XOR Execute) memory protection. JIT compilation is blocked on real devices. `Dala.ML.EMLX.setup/0` sets `LIBMLX_ENABLE_JIT=false` automatically for devices.

2. **iOS Simulator**: JIT works in the simulator. `Dala.ML.EMLX.setup/0` enables it automatically.

3. **Metal GPU**: EMLX uses MLX which leverages Apple's Metal framework. The unified memory architecture of Apple Silicon makes CPU↔GPU data transfer essentially free.

4. **64-bit Floats**: Metal doesn't support 64-bit floats. MLX and EMLX use 32-bit floats.

### Device vs Simulator

```elixir
# Check if running on iOS device or simulator
Dala.ML.EMLX.ios_device?()    # true for real device
Dala.ML.EMLX.ios_simulator?() # true for simulator

# Get platform-appropriate config
Dala.ML.EMLX.platform_config()
# Returns %{device: :gpu, jit_enabled: false, metal_jit: false} for device
```

## Example: Simple Neural Network

```elixir
defmodule MyApp.Model do
  require Axon

  def create_model do
    Axon.input("input", shape: {nil, 784})
    |> Axon.dense(128, activation: :relu)
    |> Axon.dropout(rate: 0.5)
    |> Axon.dense(10, activation: :softmax)
  end

  def train(model, data, labels) do
    model
    |> Axon.Loop.trainer(:categorical_cross_entropy, Axon.Optimizers.adam(0.001))
    |> Axon.Loop.run(data, labels, epochs: 10)
  end
end
```

## Building for iOS

### Native Build with EMLX

EMLX requires the MLX library. The build process:

1. **For iOS Simulator**: Standard `mix dala.deploy --native` should work.

2. **For iOS Device**: Cross-compile MLX for iOS arm64:
   - Download precompiled MLX iOS binaries from [mlx-build](https://github.com/cocoa-xu/mlx-build)
   - Or build from source with iOS SDK

3. **Disable JIT in OTP**: Ensure your OTP build has `--disable-jit` flag.

### Environment Variables

```bash
# Disable JIT for iOS device builds
export LIBMLX_ENABLE_JIT=false

# Use specific MLX version
export LIBMLX_VERSION=0.31.2

# Cache directory for downloaded binaries
export LIBMLX_CACHE=~/.cache/libmlx
```

## Limitations

1. **64-bit float operations**: Not supported by Metal. Use 32-bit floats.

2. **Model training**: While possible, training large models on-device is limited by memory and compute. Consider:
   - Training in the cloud, deploying to device
   - Using pre-trained models
   - Quantization for smaller models (EMLX supports 4-bit quantization)

## Troubleshooting

### "JIT not allowed" errors
Ensure `LIBMLX_ENABLE_JIT=false` and OTP is built with `--disable-jit`.

### "MLX not found" errors
Check that MLX binaries are available for iOS arm64. You may need to:
1. Set `LIBMLX_BUILD=true` to build from source
2. Or provide precompiled binaries via `MLX_ARCHIVE_PATH`

### Memory issues
Use `EMLX.clear_cache/0` and `EMLX.set_memory_limit/1` to manage GPU memory.

## See Also

- [EMLX Documentation](https://hexdocs.pm/emlx)
- [Nx Documentation](https://hexdocs.pm/nx)
- [Axon Documentation](https://hexdocs.pm/axon)
- [MLX GitHub](https://github.com/ml-explore/mlx)
