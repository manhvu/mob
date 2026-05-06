// DalaDemo-Bridging-Header.h — Exposes Dala ObjC types to Swift.
// Passed to swiftc via -import-objc-header.

#import "DalaNode.h"

// Called from DalaHostingController to signal a back gesture to the BEAM.
// Implemented in dala_nif.m; looks up :dala_screen and sends {:dala, :back}.
void dala_handle_back(void);

// Called from DalaRootView.swift WebView delegate when JS sends a message or a URL is blocked.
// Implemented in dala_nif.m; looks up :dala_screen and sends the appropriate tuple.
void dala_deliver_webview_message(const char* json_utf8);
void dala_deliver_webview_blocked(const char* url_utf8);

// Called from DalaNativeViewRegistry.send closure when a native view fires an event.
// Implemented in dala_nif.m; looks up the component pid by handle and delivers
// {:component_event, event, payload_json} to it.
void dala_send_component_event(int handle, const char* event, const char* payload_json);

// Called from DalaRootView.swift's .onChange(of: colorScheme) modifier when
// the OS appearance toggles (light/dark). Dispatches to Dala.Device subscribers.
// `scheme` is "light" or "dark".
void dala_notify_color_scheme(const char* scheme);

// Bluetooth (BLE) C interface functions
// Called from Rust to interact with iOS CoreBluetooth
void DalaBluetoothSetDeviceFoundCallback(void (*callback)(const char*, const char*, int, const char*));
void DalaBluetoothSetDeviceConnectedCallback(void (*callback)(const char*));
void DalaBluetoothSetDeviceConnectFailedCallback(void (*callback)(const char*, const char*));
void DalaBluetoothSetDeviceDisconnectedCallback(void (*callback)(const char*));
void DalaBluetoothSetServicesDiscoveredCallback(void (*callback)(const char*, const char*, const char*));
void DalaBluetoothSetCharacteristicReadCallback(void (*callback)(const char*, const char*, const char*, const uint8_t*, size_t, const char*));
void DalaBluetoothSetCharacteristicWrittenCallback(void (*callback)(const char*, const char*, const char*, const char*));
void DalaBluetoothSetCharacteristicNotifiedCallback(void (*callback)(const char*, const char*, const char*, const uint8_t*, size_t));

const char* DalaBluetoothGetState(void);
void DalaBluetoothStartScan(const char** serviceUUIDs, int serviceCount, unsigned long timeoutMs);
void DalaBluetoothStopScan(void);
void DalaBluetoothConnect(const char* identifier);
void DalaBluetoothDisconnect(const char* identifier);
void DalaBluetoothDiscoverServices(const char* identifier);
void DalaBluetoothReadCharacteristic(const char* identifier, const char* serviceUUID, const char* characteristicUUID);
void DalaBluetoothWriteCharacteristic(const char* identifier, const char* serviceUUID, const char* characteristicUUID, const uint8_t* value, size_t valueLen);
void DalaBluetoothSubscribe(const char* identifier, const char* serviceUUID, const char* characteristicUUID);
void DalaBluetoothUnsubscribe(const char* identifier, const char* serviceUUID, const char* characteristicUUID);
