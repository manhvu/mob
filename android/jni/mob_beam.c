// mob_beam.c — Mob BEAM launcher and JNI bridge initialisation.
// Extracted from the per-app beam_jni.c stub so app code stays minimal.

#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "mob_beam.h"

#define LOG_TAG "MobBeam"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define OTP_ROOT    "/data/data/com.mob.demo/files/otp"
#define ERTS_VSN    "erts-16.3"
#define BEAMS_DIR   OTP_ROOT "/beamhello"
#define ELIXIR_DIR  OTP_ROOT "/lib/elixir/ebin"
#define LOGGER_DIR  OTP_ROOT "/lib/logger/ebin"

// Declared in mob_nif.c — caches MobBridge methods on the main thread.
extern void _mob_ui_cache_class_impl(JNIEnv* env, const char* bridge_class);

// Declared in mob_nif.c — the C function registered as the tap native.
extern void mob_native_on_tap(JNIEnv* jenv, jclass cls, jlong ptr);

void mob_ui_cache_class(JNIEnv* env, const char* bridge_class) {
    _mob_ui_cache_class_impl(env, bridge_class);
}

void mob_register_tap_native(JNIEnv* env, const char* tap_class) {
    jclass cls = (*env)->FindClass(env, tap_class);
    if (!cls) { LOGE("mob_register_tap_native: class %s not found", tap_class); return; }
    JNINativeMethod methods[] = {
        {"nativeOnTap", "(J)V", (void*)mob_native_on_tap}
    };
    (*env)->RegisterNatives(env, cls, methods, 1);
    (*env)->DeleteLocalRef(env, cls);
    LOGI("mob_register_tap_native: registered nativeOnTap on %s", tap_class);
}

// Declared in mob_nif.c — the cached Bridge.cls global ref.
extern void _mob_bridge_init_activity(JNIEnv* env, jobject activity);

void mob_init_bridge(JNIEnv* env, jobject activity) {
    g_activity = (*env)->NewGlobalRef(env, activity);
    _mob_bridge_init_activity(env, g_activity);
}

void mob_start_beam(const char* app_module) {
    setenv("BINDIR",   OTP_ROOT "/" ERTS_VSN "/bin", 1);
    setenv("ROOTDIR",  OTP_ROOT, 1);
    setenv("PROGNAME", "erl", 1);
    setenv("EMU",      "beam", 1);
    setenv("HOME",     "/data/data/com.mob.demo/files", 1);
    setenv("ERL_CRASH_DUMP", "/data/data/com.mob.demo/files/erl_crash.dump", 1);
    setenv("ERL_CRASH_DUMP_SECONDS", "30", 1);

    // Build "-eval Module:start()." dynamically from app_module.
    // Max module name length is 255; ".:start()." is 10 chars + NUL.
    char eval_expr[280];
    snprintf(eval_expr, sizeof(eval_expr), "%s:start().", app_module);

    const char* args[] = {
        "beam",
        "-S", "1:1", "-SDcpu", "1:1", "-SDio", "1", "-A", "1", "-sbwt", "none",
        "--",
        "-root",     OTP_ROOT,
        "-bindir",   OTP_ROOT "/" ERTS_VSN "/bin",
        "-progname", "erl",
        "--",
        "-noshell", "-noinput",
        "-boot",   OTP_ROOT "/releases/29/start_clean",
        "-pa",     ELIXIR_DIR,
        "-pa",     LOGGER_DIR,
        "-pa",     BEAMS_DIR,
        "-eval",   eval_expr,
        NULL
    };
    int ac = 0;
    while (args[ac]) ac++;
    LOGI("mob_start_beam: starting BEAM with module=%s, argc=%d", app_module, ac);

    void erl_start(int, char**);
    erl_start(ac, (char**)args);
    LOGE("mob_start_beam: erl_start returned (unexpected)");
}
