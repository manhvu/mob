# ONNX Runtime for macOS

This directory should contain the ONNX Runtime library for macOS (for testing).

## Download Instructions

1. Go to: https://github.com/microsoft/onnxruntime/releases
2. Download the macOS package: `onnxruntime-osx-<version>.tgz`
3. Extract and copy the library:
   ```bash
   tar -xzf onnxruntime-osx-*.tgz
   cp onnxruntime-osx-*/lib/libonnxruntime.dylib native/onnxruntime-macos/lib/
   cp onnxruntime-osx-*/lib/libonnxruntime.1.17.0.dylib native/onnxruntime-macos/lib/
   ```

## Required Files

- `libonnxruntime.dylib` - Main ONNX Runtime library
- `libonnxruntime.1.17.0.dylib` - Versioned symlink

## Verification

```bash
file native/onnxruntime-macos/lib/libonnxruntime.dylib
# Should show: Mach-O 64-bit dynamically linked shared library
```

## Notes

- Use version 1.17.0 or later
- For macOS: x86_64 architecture (Intel) or arm64 (Apple Silicon)
- Use for testing ONNX Runtime integration on macOS before iOS/Android builds
