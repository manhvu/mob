# Android.mk for integrating Rust libraries
# Place this in dala/android/jni/Android.mk

LOCAL_PATH := $(call my-dir)

# ============================================================================
# Rust library (dala_beam)
# ============================================================================
include $(CLEAR_VARS)

LOCAL_MODULE := dala_beam_rust
LOCAL_SRC_FILES := rust/target/$(TARGET_ARCH_ABI)/release/libdala_beam.so

# Ensure Rust is built before this module
LOCAL_ADDITIONAL_DEPENDENCIES := \
    $(LOCAL_PATH)/rust/target/$(TARGET_ARCH_ABI)/release/libdala_beam.so

LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)
LOCAL_EXPORT_LDLIBS := -llog

include $(PREBUILT_SHARED_LIBRARY)

# ============================================================================
# Driver table (driver_tab_android)
# ============================================================================
include $(CLEAR_VARS)

LOCAL_MODULE := driver_tab_android_rust
LOCAL_SRC_FILES := rust/target/$(TARGET_ARCH_ABI)/release/libdriver_tab_android.a

LOCAL_ADDITIONAL_DEPENDENCIES := \
    $(LOCAL_PATH)/rust/target/$(TARGET_ARCH_ABI)/release/libdriver_tab_android.a

LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)
LOCAL_STATIC_LIBRARIES := dala_beam_rust

include $(PREBUILT_STATIC_LIBRARY)

# ============================================================================
# Build Rust before NDK build
# ============================================================================
$(LOCAL_PATH)/rust/target/%/release/libdala_beam.so:
	cd $(LOCAL_PATH)/rust && ./build_android.sh

$(LOCAL_PATH)/rust/target/%/release/libdriver_tab_android.a:
	cd $(LOCAL_PATH)/rust && ./build_android.sh
