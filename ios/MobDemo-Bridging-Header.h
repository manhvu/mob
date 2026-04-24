// MobDemo-Bridging-Header.h — Exposes Mob ObjC types to Swift.
// Passed to swiftc via -import-objc-header.

#import "MobNode.h"

// Called from MobHostingController to signal a back gesture to the BEAM.
// Implemented in mob_nif.m; looks up :mob_screen and sends {:mob, :back}.
void mob_handle_back(void);

// Called from MobRootView.swift WebView delegate when JS sends a message or a URL is blocked.
// Implemented in mob_nif.m; looks up :mob_screen and sends the appropriate tuple.
void mob_deliver_webview_message(const char* json_utf8);
void mob_deliver_webview_blocked(const char* url_utf8);
