// mob_beam.m — Mob BEAM launcher for iOS.
// Extracted from the per-app beam_main.m stub so app code stays minimal.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#include "mob_beam.h"

#define OTP_ROOT   "/tmp/otp-ios-sim"
#define ERTS_VSN   "erts-16.3"
#define BEAMS_DIR  OTP_ROOT "/beamhello"
#define ELIXIR_DIR OTP_ROOT "/lib/elixir/ebin"
#define LOGGER_DIR OTP_ROOT "/lib/logger/ebin"

UIViewController* g_root_vc = nil;

void mob_init_ui(UIViewController* root_vc) {
    g_root_vc = root_vc;
    NSLog(@"[MobBeam] mob_init_ui: root_vc=%@", root_vc);
}

void mob_start_beam(const char* app_module) {
    setenv("BINDIR",   OTP_ROOT "/" ERTS_VSN "/bin", 1);
    setenv("ROOTDIR",  OTP_ROOT, 1);
    setenv("PROGNAME", "erl", 1);
    setenv("EMU",      "beam", 1);
    setenv("HOME",     "/tmp", 1);
    setenv("ERL_CRASH_DUMP", "/tmp/mob_erl_crash.dump", 1);
    setenv("ERL_CRASH_DUMP_SECONDS", "30", 1);

    // Build "-eval Module:start()." dynamically from app_module.
    // Using -eval avoids the -s path in init which has a version mismatch
    // in OTP 29 RC2's preloaded init.beam.
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
    NSLog(@"[MobBeam] mob_start_beam: starting BEAM module=%s argc=%d", app_module, ac);

    void erl_start(int, char**);
    erl_start(ac, (char**)args);
    NSLog(@"[MobBeam] mob_start_beam: erl_start returned (unexpected)");
}
