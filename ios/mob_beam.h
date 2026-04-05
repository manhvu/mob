// mob_beam.h — Public API for mob's BEAM launcher on iOS.
// Include this in your app's beam_main.m stub.

#ifndef MOB_BEAM_H
#define MOB_BEAM_H

#import <UIKit/UIKit.h>

// Call from application:didFinishLaunchingWithOptions: (main thread).
// Stores the root view controller so set_root NIF can replace its content.
void mob_init_ui(UIViewController* root_vc);

// Call mob_start_beam on a background thread — erl_start never returns.
// app_module: Erlang module name, e.g. "mob_demo"
void mob_start_beam(const char* app_module);

// Global root view controller — used by mob_nif set_root.
extern UIViewController* g_root_vc;

#endif // MOB_BEAM_H
