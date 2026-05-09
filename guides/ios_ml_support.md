# iOS ML Support Guide

This guide covers adding machine learning capabilities to Dala apps on iOS using the Nx ecosystem.

## Overview

For iOS development, these ML backends are supported:

| Component | Status | Notes |
|-----------|--------|-------|
| **Nx** | ✅ Ready | Pure Elixir, works on any platform |
| **Axon** | ✅ Ready | Neural networks, pure Elixir |
| **Scholar** | ✅ Ready | Traditional ML (regression, clustering, SVM) |
| **NxSignal** | ✅ Ready | Digital signal processing |
| **EMLX** | ✅ Zero-config | MLX backend — **recommended for iOS** |
| **CoreML** | ✅ Ready | Apple Neural Engine, iOS-native |
| **ONNX Runtime** | ⚠️ Placeholder | Cross-platform, structure ready |

**Not supported on iOS:** Emily (macOS-only), NxIREE, EXLA/XLA, Torchx.

## Quick Start

### 1. Zero-Config Setup (Recommended)

`Dala.ML.setup/0` auto-configures everything based on platform:

```elixir
defmodule MyApp.App do
  use Dala.App

  def start(_type, _args) do
    # Auto-configures based on platform:
    # - iOS device: EMLX with Metal GPU, JIT disabled (W^X policy)
    # - iOS simulator: EMLX with Metal GPU, JIT enabled
    # - Android: Nx.BinaryBackend
    # - Other: Nx.BinaryBackend
    Dala.ML.setup()

    # ... rest of your app startup
  end
end
```

No manual `config :nx, ...` or `config :emlx, ...` needed!

### 2. Verify Setup

```elixir
# Check ML stack status
Dala.ML.status()
# %{platform: :ios_device, backend: {EMLX.Backend, [device: :gpu]}, ...}

# Quick verification
Dala.ML.verify()
# %{status: :ok, sum: 6.0, backend: {EMLX.Backend, [device: :gpu]}}

# Available backends
Dala.ML.available_backends()
# [:nx, :emlx, :coreml, :onnx]

# Benchmark
Dala.ML.benchmark(size: 100, iterations: 10)
# %{time_ms: 1.234, gflops: 0.857, ...}
```

### 3. Use ML Libraries

```elixir
# Nx tensors (auto-configured backend)
tensor = Nx.tensor([1.0, 2.0, 3.0])
Nx.sum(tensor)

# Axon neural networks
model = Axon.input("input", shape: {nil, 784})
       |> Axon.dense(128, activation: :relu)
       |> Axon.dense(10, activation: :softmax)

# Scholar traditional ML
model = Scholar.LinearRegression.fit(features, targets)

# NxSignal DSP
filtered = NxSignal.butterworth(signal, cutoff: 0.2)
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

### Default Device

```elixir
# Returns the default EMLX device
Dala.ML.EMLX.default_device()
# :gpu on iOS, :cpu on other platforms
```

## CoreML on iOS

### Loading and Running Models

```elixir
# Load a CoreML model
:ok = Dala.ML.CoreML.load_model("/path/to/model.mlmodel", "my_model")

# Check if loaded
true = Dala.ML.CoreML.loaded?("my_model")

# Make prediction (synchronous, runs on dirty CPU scheduler)
{:ok, result_json} = Dala.ML.CoreML.predict("my_model", %{
  "input1" => 1.0,
  "input2" => [1.0, 2.0, 3.0]
})

# Parse result
result = Jason.decode!(result_json)

# Unload when done
:ok = Dala.ML.CoreML.unload_model("my_model")
```

### Converting Models to CoreML

1. **Axon → ONNX → CoreML**:
   ```elixir
   # Train with Axon
   model = Axon.input("input", shape: {nil, 784}) |> Axon.dense(10, activation: :softmax)
   {init_fn, predict_fn} = Axon.build(model)
   params = init_fn.(Nx.template({1, 784}, :f32), %{})

   # Export to ONNX (requires ortonx or onnx package)
   # Then convert ONNX to CoreML using Apple's coremltools (Python)
   ```

2. **Use pre-trained CoreML models** from Apple or third parties.

### Input Types

CoreML supports these input types in the `inputs` map:

| Type | Example | CoreML Mapping |
|------|---------|---------------|
| Number | `1.0` | `MLFeatureValue(double:)` |
| String | `"hello"` | `MLFeatureValue(string:)` |
| List | `[1.0, 2.0, 3.0]` | `MLMultiArray` |
| Binary | `<<...>>` | `MLFeatureValue(data:)` |

## ONNX Runtime (Cross-Platform)

### Status

ONNX Runtime integration is currently a **placeholder**. The Rust NIF layer and
`dala_onnx` crate have correct structure and thread-safe session management, but
actual ONNX Runtime linking and inference is not yet implemented.

### Setup (When Available)

```bash
# Download ONNX Runtime for iOS
cd native/onnxruntime-ios/
# See native/ONNX_RUNTIME_SETUP.md for download instructions
```

### Usage (When Available)

```elixir
# Create session from ONNX model data
{:ok, session_id} = Dala.ML.ONNX.create_session(model_data)

# Or load from file
{:ok, session_id} = Dala.ML.ONNX.load_model_from_file("model.onnx")

# Run inference
{:ok, output} = Dala.ML.ONNX.run(session_id, input_binary)

# Clean up
:ok = Dala.ML.ONNX.destroy_session(session_id)
```

## Unified API

`Dala.ML.predict/2` dispatches to the right backend based on model type:

```elixir
# CoreML model (string identifier on iOS)
Dala.ML.predict("my_model", %{"input" => [1.0, 2.0, 3.0]})

# ONNX session (integer session ID)
Dala.ML.predict(session_id, input_binary)

# Axon model ({model, params} tuple)
Dala.ML.predict({axon_model, params}, input_tensor)
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

## Nx Integration

`Dala.Ml.Nx` provides helpers for backend selection and inference:

```elixir
# Initialize Nx with the best available backend
Dala.Ml.Nx.init()

# Create a tensor with the default backend
tensor = Dala.Ml.Nx.tensor([1.0, 2.0, 3.0])

# Run inference with an Axon model
{:ok, output} = Dala.Ml.Nx.inference(model, params, input_tensor)

# Check if Axon is available
Dala.Ml.Nx.axon_available?()
```

### Backend Priority

1. **EMLX** (if available) — best for Apple Silicon
2. **Nx.BinaryBackend** — pure Elixir fallback

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

## Dependencies

The following dependencies are included in `mix.exs` for ML support:

| Dependency | Version | Purpose |
|------------|---------|---------|
| `:nx` | `~> 0.10` | Core tensor library |
| `:polaris` | `~> 0.1` | Nx compiler |
| `:scholar` | `~> 0.4.0` | Traditional ML algorithms |
| `:nx_signal` | `~> 0.3.0` | Digital signal processing |
| `:axon` | `~> 0.8.0` | Neural network library |

## Limitations

1. **64-bit float operations**: Not supported by Metal. Use 32-bit floats.

2. **Model training**: While possible, training large models on-device is limited by memory and compute. Consider:
   - Training in the cloud, deploying to device
   - Using pre-trained models
   - Quantization for smaller models (EMLX supports 4-bit quantization)

3. **ONNX Runtime**: Currently placeholder only. Real inference requires linking the ONNX Runtime C library.

## Troubleshooting

### "JIT not allowed" errors
Ensure `LIBMLX_ENABLE_JIT=false` and OTP is built with `--disable-jit`.
`Dala.ML.EMLX.setup/0` handles this automatically.

### "MLX not found" errors
Check that MLX binaries are available for iOS arm64. You may need to:
1. Set `LIBMLX_BUILD=true` to build from source
2. Or provide precompiled binaries via `MLX_ARCHIVE_PATH`

### Memory issues
Use `EMLX.clear_cache/0` and `EMLX.set_memory_limit/1` to manage GPU memory.

### CoreML returns `:not_supported`
- CoreML is only available on iOS
- Ensure model file exists at the specified path
- Check model format (.mlmodel or .mlpackage)

### ONNX `available?/0` returns `false`
- ONNX Runtime NIF must be compiled for the target platform
- Verify ONNX Runtime libraries are in `native/onnxruntime-ios/`

## See Also

- [EMLX Documentation](https://hexdocs.pm/emlx)
- [Nx Documentation](https://hexdocs.pm/nx)
- [Axon Documentation](https://hexdocs.pm/axon)
- [MLX GitHub](https://github.com/ml-explore/mlx)
- [ONNX Runtime Setup](../native/ONNX_RUNTIME_SETUP.md)
- [ML Integration Summary](../dala/ML_INTEGRATION_SUMMARY.md)