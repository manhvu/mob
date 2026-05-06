# ONNX Runtime for macOS

## Setup Instructions

1. Download the appropriate package for your Mac:

   **Apple Silicon (M1/M2/M3)**:
   https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-osx-arm64-1.17.0.tgz

   **Intel Mac**:
   https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-osx-x86_64-1.17.0.tgz

2. Extract the archive:
   ```bash
   tar -xzf onnxruntime-osx-arm64-1.17.0.tgz
   ```

3. Copy the library to `lib/` directory:
   ```bash
   cp onnxruntime-osx-arm64-1.17.0/lib/libonnxruntime.dylib lib/
   ```

## Required Files

- `libonnxruntime.dylib` (for macOS development/testing)

## Verification

```bash
ls -la lib/
```

Should show `libonnxruntime.dylib`.

## Note

This is for development and testing on macOS. iOS and Android builds use their respective directories.
