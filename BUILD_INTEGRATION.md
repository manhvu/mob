# Build Integration Guide

## Overview
This guide explains how to integrate the Rust libraries into the existing Android and iOS build systems.

## Prerequisites

### Android
- Rust installed (https://rustup.rs)
- Android NDK installed and `ANDROID_NDK_HOME` or `ANDROID_HOME` set
- Targets installed: `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`

### iOS
- Rust installed (https://rustup.rs)
- Targets installed: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
- Xcode command line tools installed

---

## Android Integration

### Option 1: Using Android.mk (Recommended)

1. **Place `Android.mk`** in `dala/android/jni/Android.mk` (already created)

2. **Update your project's `Application.mk`** to reference the new module:
   ```makefile
   APP_MODULES := driver_tab_android_rust dala_beam_rust
   ```

3. **Build with ndk-build**:
   ```bash
   cd dala/android/jni
   ndk-build
   ```

### Option 2: Using CMake (if using CMakeLists.txt)

Create `dala/android/jni/CMakeLists.txt`:
```cmake
cmake_minimum_required(VERSION 3.10)

# Build Rust libraries first
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/rust/target/aarch64-linux-android/release/libdala_beam.so
    COMMAND cd ${CMAKE_CURRENT_SOURCE_DIR}/rust && ./build_android.sh
    COMMENT "Building Rust libraries for Android"
)

# Import Rust libraries
add_library(dala_beam_rust SHARED IMPORTED)
set_target_properties(dala_beam_rust PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/rust/target/aarch64-linux-android/release/libdala_beam.so
)

add_library(driver_tab_android_rust STATIC IMPORTED)
set_target_properties(driver_tab_android_rust PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/rust/target/aarch64-linux-android/release/libdriver_tab_android.a
)

# Your main library that links against these
add_library(dala_beam SHARED dala_beam.c)
target_link_libraries(dala_beam dala_beam_rust driver_tab_android_rust log)
```

### Step 4: Link Order

**Important**: Link Rust libraries BEFORE `libbeam.a`:
```makefile
# In your main Android.mk
LOCAL_STATIC_LIBRARIES := driver_tab_android_rust
LOCAL_SHARED_LIBRARIES := dala_beam_rust libbeam
```

---

## iOS Integration

### Step 1: Add Build Phase Script

1. Open your Xcode project
2. Select your target → **Build Phases**
3. Click **+** → **New Run Script Phase**
4. Name it "Build Rust Libraries"
5. Move it BEFORE "Compile Sources"
6. Add this script:
   ```bash
   "$SRCROOT/ios/xcode_build_rust.sh"
   ```

### Step 2: Link the Libraries

1. In Xcode, go to **Build Settings** → **Link Binary With Libraries**
2. Click **+** and add:
   - `libdala_beam_ios_device.a` (for device)
   - `libdala_beam_ios_simulator.a` (for simulator)
   - `libdriver_tab_ios_device.a`
3. Ensure the libraries are in the **Frameworks** folder (created by the build script)

### Step 3: Set Library Search Paths

In **Build Settings** → **Library Search Paths**, add:
```
$(SRCROOT)/ios/Frameworks
```

### Step 4: Feature Flags (Optional)

To enable specific features, add to **Build Settings** → **Other C Flags**:
```
-Ddala_BUNDLE_OTP
-Ddala_RELEASE
```

Or modify `dala/ios/rust/Cargo.toml`:
```toml
[features]
default = ["dala_bundle_otp"]  # Enable for device builds
```

### Step 5: Gradual Migration

1. **Test driver tables first** (they're complete):
   - Replace `driver_tab_ios.c` with `libdriver_tab_ios.a` in linking
   - Keep `dala_beam.m` for now

2. **Test BEAM launcher**:
   - Once `erl_start` linking is verified
   - Replace `dala_beam.m` with `libdala_beam_ios.a`
   - Remove `dala_beam.m` from Xcode project

3. **Full migration**:
   - Remove all C files (`driver_tab_*.c`, `dala_beam.c`, `dala_beam.m`)
   - Use only Rust libraries

---

## Verification

### Android
```bash
# Check if Rust libraries were built
ls -la dala/android/jni/rust/target/*/release/*.so
ls -la dala/android/jni/rust/target/*/release/*.a

# Test loading the library
adb push dala/android/jni/rust/target/aarch64-linux-android/release/libdala_beam.so /data/local/tmp/
```

### iOS
```bash
# Check if Rust libraries were built
ls -la dala/ios/rust/target/*/release/*.a

# Check universal library
lipo -info dala/ios/Frameworks/libdala_beam_ios_simulator.a
# Should show: Architectures in the fat file: x86_64 arm64
```

---

## Troubleshooting

### Android
- **NDK not found**: Set `ANDROID_NDK_HOME` or `ANDROID_HOME`
- **Linking errors**: Ensure `libbeam.a` is linked AFTER Rust libraries
- **JNI errors**: Check that function names match exactly (use `nm -D libdala_beam.so | grep dala_`)

### iOS
- **Rust not found**: Install from https://rustup.rs
- **Target not found**: Run `rustup target add aarch64-apple-ios`
- **Duplicate symbols**: Make sure you removed the C files from Xcode project
- **Bitcode issues**: Disable bitcode in Xcode build settings

---

## Next Steps

1. **Test on simulator first** (easier debugging)
2. **Test on device** (more complex, requires provisioning)
3. **Compare behavior** between C and Rust versions
4. **Remove C files** only after thorough testing
5. **Update CI/CD** to include Rust build steps
