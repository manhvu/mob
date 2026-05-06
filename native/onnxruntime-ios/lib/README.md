# ONNX Runtime for iOS

This directory should contain the ONNX Runtime library for iOS.

## Download Instructions

1. Go to: https://github.com/microsoft/onnxruntime/releases
2. Download the iOS package: `onnxruntime-osx-arm64-<version>.tgz`
3. Extract and copy the library:
   ```bash
   tar -xzf onnxruntime-osx-arm64-*.tgz
   cp onnxruntime-osx-arm64-*/lib/libonnxruntime.dylib native/onnxruntime-ios/lib/
   cp onnxruntime-osx-arm64-*/lib/libonnxruntime.0.1.0.dylib native/onnxruntime-ios/lib/
   ```

## Required Files

- `libonnxruntime.dylib` - Main ONNX Runtime library
- `libonnxruntime.0.1.0.dylib` - Versioned symlink

## Verification

```bash
file native/onnxruntime-ios/lib/libonnxruntime.dylib
# Should show: Mach-O 64-bit dynamically linked shared library
```

## Notes

- Use version 1.17.0 or later
- For iOS device: arm64 architecture
- For iOS simulator: x86_64 architecture (if needed)
