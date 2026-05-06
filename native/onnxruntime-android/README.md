# ONNX Runtime for Android

## Setup Instructions

1. Download `onnxruntime-android-1.17.0.aar` from:
   https://github.com/microsoft/onnxruntime/releases/download/v1.17.0/onnxruntime-android-1.17.0.aar

   Alternative (smaller): `onnxruntime-mobile-android-1.17.0.tgz`

2. Extract the AAR (it's a zip file):
   ```bash
   mkdir extracted && cd extracted
   unzip ../onnxruntime-android-1.17.0.aar
   ```

3. Copy JNI libraries to appropriate directories:
   ```bash
   cp extracted/jni/arm64-v8a/*.so jni/arm64-v8a/
   cp extracted/jni/armeabi-v7a/*.so jni/armeabi-v7a/
   cp extracted/jni/x86_64/*.so jni/x86_64/
   cp extracted/jni/x86/*.so jni/x86/
   ```

## Required Files

- `libonnxruntime.so` for each architecture:
  - `jni/arm64-v8a/` (ARM64 - most devices)
  - `jni/armeabi-v7a/` (ARM32 - older devices)
  - `jni/x86_64/` (x86_64 emulator)
  - `jni/x86/` (x86 emulator)

## Verification

```bash
ls -la jni/arm64-v8a/
```

Should show `libonnxruntime.so`.
