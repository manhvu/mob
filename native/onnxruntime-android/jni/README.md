# ONNX Runtime for Android

This directory should contain the ONNX Runtime library for Android.

## Download Instructions

1. Go to: https://github.com/microsoft/onnxruntime/releases
2. Download the Android package: `onnxruntime-android-<version>.tgz`
3. Extract and copy the libraries:
   ```bash
   tar -xzf onnxruntime-android-*.tgz
   cp onnxruntime-android-*/jni/arm64-v8a/libonnxruntime.so native/onnxruntime-android/jni/arm64-v8a/
   cp onnxruntime-android-*/jni/armeabi-v7a/libonnxruntime.so native/onnxruntime-android/jni/armeabi-v7a/
   ```

## Required Files

- `libonnxruntime.so` - Main ONNX Runtime library (arm64-v8a)
- `libonnxruntime.so` - Main ONNX Runtime library (armeabi-v7a)

## Verification

```bash
file native/onnxruntime-android/jni/arm64-v8a/libonnxruntime.so
# Should show: ELF 64-bit LSB shared object, ARM aarch64
```

## Notes

- Use version 1.17.0 or later
- For Android: arm64-v8a (64-bit) and armeabi-v7a (32-bit)
- NNAPI EP is available on Android 8.1+ (API level 27+)
