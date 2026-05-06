# ONNX Runtime for iOS

## Setup Instructions

1. Download `onnxruntime-mobile-ios-1.17.0.tgz` from:
   https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-mobile-ios-1.17.0.tgz

2. Extract the archive:
   ```bash
   tar -xzf onnxruntime-mobile-ios-1.17.0.tgz
   ```

3. Copy the library/framework to `lib/` directory:
   ```bash
   cp -R onnxruntime-mobile-ios-1.17.0/lib/*.dylib lib/
   # OR if using framework:
   cp -R onnxruntime-mobile-ios-1.17.0/onnxruntime.framework lib/
   ```

## Required Files

- `libonnxruntime.dylib` (or `onnxruntime.framework`)
- Supports: arm64 (device), x86_64/arm64 (simulator)

## Verification

```bash
ls -la lib/
```

Should show ONNX Runtime libraries for iOS.
