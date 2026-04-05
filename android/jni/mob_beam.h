// mob_beam.h — Public API for mob's BEAM launcher and UI initialisation.
// Include this in your app's beam_jni.c stub.

#ifndef MOB_BEAM_H
#define MOB_BEAM_H

#include <jni.h>

// Call from JNI_OnLoad (main thread).
// bridge_class: e.g. "com/myapp/MobBridge"
// tap_class:    e.g. "com/myapp/MobTapListener"
void mob_ui_cache_class(JNIEnv* env, const char* bridge_class);
void mob_register_tap_native(JNIEnv* env, const char* tap_class);

// Call from nativeSetActivity.
void mob_init_bridge(JNIEnv* env, jobject activity);

// Call from nativeStartBeam.
// app_module: Erlang module name, e.g. "mob_demo"
void mob_start_beam(const char* app_module);

// Global JVM pointer — defined in mob_beam.c, extern'd for mob_nif.c.
extern JavaVM* g_jvm;
extern jobject g_activity;

#endif // MOB_BEAM_H
