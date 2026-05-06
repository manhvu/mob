# Dala ML Integration - Complete Summary

## Overview

This document summarizes the complete ML integration for the Dala project, providing cross-platform machine learning capabilities for iOS and Android apps written in Elixir.

## BEAM Scheduler Configuration

The BEAM VM is configured with 4 online schedulers and 1 dirty scheduler to balance performance with battery efficiency:

```rust
// Default configuration (all platforms)
-S 4:1        # 4 online schedulers, 1 dirty scheduler
-SDcpu 4:1    # 4 online dirty CPU, 1 dirty CPU
-SDio 1       # 1 dirty I/O scheduler
-A 1          # 1 async thread pool
-sbwt none    # No busy waiting
```

### Environment Variable Override

The scheduler configuration can be customized via environment variables:

- **`DALA_BEAM_SCHEDULERS`**: Sets online and dirty scheduler count (format: `"online:dirty"`)
  - Example: `DALA_BEAM_SCHEDULERS="2:2"` for 2 online, 2 dirty schedulers
  - Default: `"4:1"`

- **`DALA_BEAM_SDCPU`**: Sets dirty CPU scheduler count (format: `"online:dirty"`)
  - Example: `DALA_BEAM_SDCPU="2:2"` for 2 online dirty CPU, 2 dirty CPU
  - Default: `"4:1"`

### Rationale

**4 online schedulers** provide better parallelism for:
- UI responsiveness during ML inference
- Concurrent request handling
- Background task processing

**1 dirty scheduler** handles long-running operations without blocking:
- ML model inference (Nx, ONNX, CoreML)
- Large file processing
- Network operations

**ML operations** use the dirty CPU scheduler:

```rust
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ort_run(...) -> i32 {
    // Runs on dirty CPU scheduler
    // Does not block online schedulers
}
```

### Comparison

| Configuration | Online Schedulers | Use Case |
|--------------|-------------------|----------|
| Default (Dala) | 4 | Balanced performance for mobile |
| Original | 1 | Minimal battery usage |
| Server BEAM | num_cores | Maximum parallelism |

### Customization Example

```bash
# Use 2 online, 2 dirty schedulers (more parallelism)
export DALA_BEAM_SCHEDULERS="2:2"
mix dala.deploy

# Use 8 online schedulers for high-performance needs
export DALA_BEAM_SCHEDULERS="8:1"
mix dala.deploy

# Revert to original 1:1 configuration
export DALA_BEAM_SCHEDULERS="1:1"
mix dala.deploy
```

## Architecture

```
Elixir (Dala.ML.*)
           │
           ├─ Nx Ecosystem (Pure Elixir)
           │    ├─ Nx (tensors)
           │    ├─ Scholar (traditional ML)
           │    ├─ NxSignal (DSP)
           │    └─ Axon (neural networks)
           │
           ├─ CoreML (iOS-native)
           │    ├─ ObjC wrapper
           │    ├─ C interface
           │    └─ Rust NIF
           │
           └─ ONNX Runtime (cross-platform)
                ├─ Rust core (dala_onnx)
                ├─ Rust NIF (dala_nif)
                └─ Elixir API
```

## Components

### 1. Nx Ecosystem (Pure Elixir)

**Dependencies added to `mix.exs`:**
- `nx` ~> 0.10 - Core tensor library
- `polaris` ~> 0.1 - Optimization
- `scholar` ~> 0.4.0 - Traditional ML
- `nx_signal` ~> 0.3.0 - DSP
- `axon` ~> 0.8.0 - Neural networks

**Files:**
- `lib/dala/ml.ex` - Unified ML API
- `lib/dala/ml/nx.ex` - Nx helpers
- `test/dala/ml_test.exs` - 14 tests

**Usage:**
```elixir
Dala.ML.setup()

# Nx tensors
tensor = Nx.tensor([1.0, 2.0, 3.0])

# Scholar (traditional ML)
model = Scholar.LinearRegression.fit(features, targets)

# Axon (neural networks)
model = Axon.input("input", shape: {nil, 784})
       |> Axon.dense(128, activation: :relu)
       |> Axon.dense(10, activation: :softmax)

# NxSignal (DSP)
filtered = NxSignal.butterworth(signal, cutoff: 0.2)
```

### 2. CoreML Bridge (iOS)

**Files:**
- `ios/DalaCoreMLManager.h/m` - Objective-C wrapper
- `ios/DalaCoreMLCInterface.m` - C interface
- `native/dala_nif/src/ios.rs` - Rust NIF
- `lib/dala/ml/core_ml.ex` - Elixir API
- `test/dala/ml/core_ml_test.exs` - 3 tests

**Features:**
- Supports `.mlmodel` and `.mlpackage` formats
- Uses Apple Neural Engine (ANE) when available
- Graceful degradation on unsupported devices

**Usage:**
```elixir
Dala.ML.CoreML.load_model("MyModel.mlpackage")
{:ok, output} = Dala.ML.CoreML.predict(model_id, input_tensor)
```

### 3. ONNX Runtime (Cross-Platform)

**Files:**
- `native/dala_onnx/` - Rust wrapper with C ABI
- `native/dala_nif/src/onnx.rs` - Rust NIF
- `lib/dala/ml/onnx.ex` - Elixir API
- `test/dala/ml/onnx_test.exs` - 3 tests

**Features:**
- Cross-platform (iOS, Android, macOS, Linux)
- Execution providers: CoreML EP (iOS), NNAPI EP (Android), CPU
- Zero-copy design (caller-allocated buffers)
- Graceful degradation on unsupported platforms

**Usage:**
```elixir
{:ok, session_id} = Dala.ML.ONNX.create_session(model_data)
output = Dala.ML.ONNX.run(session_id, input_data)
```

### 4. Unified API

**File:** `lib/dala/ml.ex`

```elixir
# Setup (auto-configures based on platform)
Dala.ML.setup()

# Check available backends
Dala.ML.available_backends()
# [:nx, :coreml, :onnx] (iOS)
# [:nx, :onnx] (Android/Linux)

# Run inference (auto-selects best backend)
Dala.ML.predict(model, input)
```

## Platform Support Matrix

| Platform | Nx | CoreML | ONNX | MLX (GPU) |
|----------|----|--------|------|----------|
| iOS Device | ✅ | ✅ | ✅ | ✅ |
| iOS Simulator | ✅ | ✅ | ✅ | ✅ |
| Android | ✅ | ❌ | ✅ | ❌ |
| macOS | ✅ | ✅ | ✅ | ✅ |
| Linux | ✅ | ❌ | ✅ | ❌ |

## Testing

```bash
# Run all ML tests
mix test test/dala/ml*

# Run specific backend tests
mix test test/dala/ml_test.exs        # Nx
mix test test/dala/ml/core_ml_test.exs  # CoreML
mix test test/dala/ml/onnx_test.exs     # ONNX
```

## Performance

- **Nx**: Pure Elixir, works everywhere, good for preprocessing
- **CoreML**: Best performance on iOS (uses ANE)
- **ONNX**: Good cross-platform performance, flexible
- **MLX**: GPU acceleration on Apple Silicon

## Next Steps

1. **Model Zoo**: Pre-trained models for common tasks
2. **Conversion Tools**: ONNX export from PyTorch/TensorFlow
3. **Optimization**: Quantization, pruning, model compression
4. **Debugging**: Visualization tools for model graphs
5. **Streaming**: Real-time inference for audio/video

## Troubleshooting

### JIT Disabled on iOS
MLX requires JIT, but iOS devices enforce W^X policy. Configuration:
```elixir
# config/config.exs
config :emlx, enable_jit: System.get_env("EMLX_ENABLE_JIT") != "false"
```

### Memory Issues
Large models may exceed device memory:
- Use quantized models (INT8 instead of FP32)
- Process in smaller batches
- Enable model caching

### Slow Inference
- Ensure running on correct execution provider
- Check model is quantized for mobile
- Profile with `Dala.ML.benchmark/2`
