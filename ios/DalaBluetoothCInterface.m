// DalaBluetoothCInterface.m - C interface for Rust to call Objective-C Bluetooth code

#import "DalaBluetoothManager.h"

// C interface functions for Rust to call
#ifdef __cplusplus
extern "C" {
#endif

void DalaBluetoothSetDeviceFoundCallback(DalaBLEDeviceFoundCallback callback) {
    [[DalaBluetoothManager sharedManager] setDeviceFoundCallback:callback];
}

void DalaBluetoothSetDeviceConnectedCallback(DalaBLEDeviceConnectedCallback callback) {
    [[DalaBluetoothManager sharedManager] setDeviceConnectedCallback:callback];
}

void DalaBluetoothSetDeviceConnectFailedCallback(DalaBLEDeviceConnectFailedCallback callback) {
    [[DalaBluetoothManager sharedManager] setDeviceConnectFailedCallback:callback];
}

void DalaBluetoothSetDeviceDisconnectedCallback(DalaBLEDeviceDisconnectedCallback callback) {
    [[DalaBluetoothManager sharedManager] setDeviceDisconnectedCallback:callback];
}

void DalaBluetoothSetServicesDiscoveredCallback(DalaBLEServicesDiscoveredCallback callback) {
    [[DalaBluetoothManager sharedManager] setServicesDiscoveredCallback:callback];
}

void DalaBluetoothSetCharacteristicReadCallback(DalaBLECharacteristicReadCallback callback) {
    [[DalaBluetoothManager sharedManager] setCharacteristicReadCallback:callback];
}

void DalaBluetoothSetCharacteristicWrittenCallback(DalaBLECharacteristicWrittenCallback callback) {
    [[DalaBluetoothManager sharedManager] setCharacteristicWrittenCallback:callback];
}

void DalaBluetoothSetCharacteristicNotifiedCallback(DalaBLECharacteristicNotifiedCallback callback) {
    [[DalaBluetoothManager sharedManager] setCharacteristicNotifiedCallback:callback];
}

const char *DalaBluetoothGetState() {
    return [[[DalaBluetoothManager sharedManager] bluetoothState] UTF8String];
}

void DalaBluetoothStartScan(const char **serviceUUIDs, int serviceCount, unsigned long timeoutMs) {
    NSMutableArray *services = nil;
    if (serviceUUIDs && serviceCount > 0) {
        services = [NSMutableArray array];
        for (int i = 0; i < serviceCount; i++) {
            [services addObject:[NSString stringWithUTF8String:serviceUUIDs[i]]];
        }
    }
    [[DalaBluetoothManager sharedManager] startScanWithServices:services timeoutMs:timeoutMs];
}

void DalaBluetoothStopScan() {
    [[DalaBluetoothManager sharedManager] stopScan];
}

void DalaBluetoothConnect(const char *identifier) {
    [[DalaBluetoothManager sharedManager] connectDeviceWithIdentifier:[NSString stringWithUTF8String:identifier]];
}

void DalaBluetoothDisconnect(const char *identifier) {
    [[DalaBluetoothManager sharedManager] disconnectDeviceWithIdentifier:[NSString stringWithUTF8String:identifier]];
}

void DalaBluetoothDiscoverServices(const char *identifier) {
    [[DalaBluetoothManager sharedManager] discoverServicesForDevice:[NSString stringWithUTF8String:identifier]];
}

void DalaBluetoothReadCharacteristic(const char *identifier, const char *serviceUUID, const char *characteristicUUID) {
    [[DalaBluetoothManager sharedManager] readCharacteristic:[NSString stringWithUTF8String:characteristicUUID]
                                                forService:[NSString stringWithUTF8String:serviceUUID]
                                                  deviceId:[NSString stringWithUTF8String:identifier]];
}

void DalaBluetoothWriteCharacteristic(const char *identifier, const char *serviceUUID, const char *characteristicUUID, const uint8_t *value, size_t valueLen) {
    NSData *data = [NSData dataWithBytes:value length:valueLen];
    [[DalaBluetoothManager sharedManager] writeCharacteristic:[NSString stringWithUTF8String:characteristicUUID]
                                                    forService:[NSString stringWithUTF8String:serviceUUID]
                                                      deviceId:[NSString stringWithUTF8String:identifier]
                                                         value:data];
}

void DalaBluetoothSubscribe(const char *identifier, const char *serviceUUID, const char *characteristicUUID) {
    [[DalaBluetoothManager sharedManager] subscribeToCharacteristic:[NSString stringWithUTF8String:characteristicUUID]
                                                          forService:[NSString stringWithUTF8String:serviceUUID]
                                                              deviceId:[NSString stringWithUTF8String:identifier]];
}

void DalaBluetoothUnsubscribe(const char *identifier, const char *serviceUUID, const char *characteristicUUID) {
    [[DalaBluetoothManager sharedManager] unsubscribeFromCharacteristic:[NSString stringWithUTF8String:characteristicUUID]
                                                              forService:[NSString stringWithUTF8String:serviceUUID]
                                                                deviceId:[NSString stringWithUTF8String:identifier]];
}

#ifdef __cplusplus
}
#endif
