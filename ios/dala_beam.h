// dala_beam.h — Public API for dala's BEAM launcher on iOS.
// Include this in your app's beam_main.m stub.

#ifndef DALA_BEAM_H
#define DALA_BEAM_H

// Call from application:didFinishLaunchingWithOptions: (main thread).
// No-op in the SwiftUI build; kept for API compatibility.
void dala_init_ui(void);

// Call dala_start_beam on a background thread — erl_start never returns.
// app_module: Erlang module name, e.g. "dala_demo"
void dala_start_beam(const char* app_module);

// Update the startup status shown on screen while BEAM is initialising.
// dala_set_startup_error stalls the screen with an error message (does not crash).
// Both are safe to call from any thread.
void dala_set_startup_phase(const char* phase);
void dala_set_startup_error(const char* error);

// Call from AppDelegate didRegisterForRemoteNotificationsWithDeviceToken
// to forward the APNs device token to the BEAM as {:push_token, :ios, hex_string}.
// Convert the raw NSData to a hex string before calling.
void dala_send_push_token(const char* hex_token);

// Store a notification JSON payload that launched the app from a killed state.
// Call from application:didFinishLaunchingWithOptions: or scene:willConnectTo:
// when a remote/local notification is the launch cause. The BEAM will deliver
// it via handle_info({:notification, ...}) after the root screen is mounted.
void dala_set_launch_notification_json(const char* json);

#endif // DALA_BEAM_H
