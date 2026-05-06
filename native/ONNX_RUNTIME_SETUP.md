# ONNX Runtime Setup for Dala

This document explains how to set up ONNX Runtime libraries for cross-platform ML inference in Dala.

## Overview

Dala uses ONNX Runtime for production-ready ML inference across iOS, Android, and macOS. ONNX Runtime provides:
- **iOS**: CoreML Execution Provider (EP) for Apple Neural Engine acceleration
- **Android**: NNAPI EP for hardware acceleration
- **macOS**: CPU/CUDA EPs for development and testing

## Recommended Version

**ONNX Runtime 1.17.0 or later**

This version provides stable mobile support and improved CoreML/NNAPI integration.

## Directory Structure

```
native/
├── onnxruntime-ios/
│   └── lib/              # iOS libraries (arm64 for device, x86_64 for simulator)
├── onnxruntime-android/
│   └── jni/
│       ├── arm64-v8a/    # Android ARM64 (most devices)
│       ├── armeabi-v7a/  # Android ARM32 (older devices)
│       ├── x86_64/       # Android emulator (64-bit)
│       └── x86/          # Android emulator (32-bit)
├── onnxruntime-macos/
│   └── lib/              # macOS libraries (for development/testing)
└── ONNX_RUNTIME_SETUP.md # This file
```

## Download Links

### iOS (Device & Simulator)

**Download**: `onnxruntime-mobile-ios-1.17.0.tgz`

- **URL**: https://github.com/microsoft/onnxruntime/releases/tag/v1.17.0
- **Direct link**: `https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-mobile-ios-1.17.0.tgz`

**Contents**: Framework for iOS device (arm64) and simulator (x86_64/arm64)

**Extract to**: `native/onnxruntime-ios/`

```bash
cd native/onnxruntime-ios/
tar -xzf ~/Downloads/onnxruntime-mobile-ios-1.17.0.tgz
# Copy libonnxruntime.dylib or framework to lib/
```

### Android

**Download**: `onnxruntime-android-1.17.0.aar`

- **URL**: https://github.com/microsoft/onnxruntime/releases/tag/v1.17.0
- **Direct link**: `https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-android-1.17.0.aar`

**Alternative**: `onnxruntime-mobile-android-1.17.0.tgz` (smaller, mobile-optimized)

**Extract to**: `native/onnxruntime-android/jni/`

```bash
cd native/onnxruntime-android/
# If using .aar (it's a zip file):
unzip ~/Downloads/onnxruntime-android-1.17.0.aar -d extracted/
# Copy jni libraries to appropriate directories:
cp extracted/jni/arm64-v8a/*.so jni/arm64-v8a/
cp extracted/jni/armeabi-v7a/*.so jni/armeabi-v7a/
cp extracted/jni/x86_64/*.so jni/x86_64/
cp extracted/jni/x86/*.so jni/x86/
```

### macOS (Development/Testing)

**Download**: `onnxruntime-osx-arm64-1.17.0.tgz` (Apple Silicon) or `onnxruntime-osx-x86_64-1.17.0.tgz` (Intel)

- **URL**: https://github.com/microsoft/onnxruntime/releases/tag/v1.17.0
- **Apple Silicon**: `https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-osx-arm64-1.17.0.tgz`
- **Intel**: `https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-osx-x86_64-1.17.0.tgz`

**Extract to**: `native/onnxruntime-macos/`

```bash
cd native/onnxruntime-macos/
tar -xzf ~/Downloads/onnxruntime-osx-arm64-1.17.0.tgz
# Copy libonnxruntime.dylib to lib/
cp onnxruntime-osx-arm64-1.17.0/lib/libonnxruntime.dylib lib/
```

## Required Libraries

### iOS
- `libonnxruntime.dylib` (or `onnxruntime.framework`)
- Architecture: arm64 (device), x86_64/arm64 (simulator)

### Android
- `libonnxruntime.so` (for each architecture)
- Architectures: `arm64-v8a` (primary), `armeabi-v7a`, `x86_64`, `x86`

### macOS
- `libonnxruntime.dylib`
- Architecture: arm64 (Apple Silicon) or x86_64 (Intel)

## Verification

After extracting libraries, verify the setup:

### Check iOS
```bash
ls -la native/onnxruntime-ios/lib/
# Should show: libonnxruntime.dylib or onnxruntime.framework
```

### Check Android
```bash
ls -la native/onnxruntime-android/jni/arm64-v8a/
# Should show: libonnxruntime.so
```

### Check macOS
```bash
ls -la native/onnxruntime-macos/lib/
# Should show: libonnxruntime.dylib
```

### Test with Dala
```elixir
# In IEx (dev environment with Dala.ML.ONNX available)
Dala.ML.ONNX.test_setup()
```

## Integration with Dala

Once libraries are in place:

1. **Rust NIF** (`native/dala_onnx/`): Links against ONNX Runtime
2. **iOS build**: Copies `onnxruntime-ios/lib/` to app bundle
3. **Android build**: Includes `.so` files in APK
4. **Elixir module**: `Dala.ML.ONNX` provides the high-level API

## Notes

- **Mobile packages**: Use `onnxruntime-mobile-*` packages for smaller size (no unnecessary EPs)
- **Version compatibility**: Ensure all platforms use the same ONNX Runtime version
- **Git tracking**: These libraries are NOT committed to git (see `.gitignore`)
- **Build scripts**: `mix dala.setup_onnx` can automate this process (future feature)

## Troubleshooting

**Library not found error**:
- Verify the library is in the correct directory
- Check architecture matches target platform
- Ensure library has correct permissions (`chmod +x *.dylib *.so`)

**Version mismatch**:
- Use same major.minor version across all platforms
- Check `onnxruntime-ios/lib/` and `onnxruntime-android/jni/` have compatible versions

**CoreML not available on iOS**:
- Ensure using `onnxruntime-mobile-ios` or full package with CoreML EP
- Check iOS deployment target ≥ 12.0

## References

- [ONNX Runtime Releases](https://github.com/microsoft/onnxruntime/releases)
- [ONNX Runtime Mobile](https://onnxruntime.ai/docs/execution-providers/mobile.html)
- [CoreML EP Documentation](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- [NNAPI EP Documentation](https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html)
- [Dala ONNX Module](lib/dala/ml/onnx.ex)
