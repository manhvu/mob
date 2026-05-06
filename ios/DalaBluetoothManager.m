// DalaBluetoothManager.m - iOS CoreBluetooth wrapper implementation

#import "DalaBluetoothManager.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface DalaBluetoothDevice ()
@end

@implementation DalaBluetoothDevice
@end

@interface DalaBluetoothManager ()

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DalaBluetoothDevice *> *discoveredDevices;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *connectedPeripherals;
@property (nonatomic, strong) dispatch_queue_t bleQueue;
@property (nonatomic, assign) BOOL scanning;

// Callback function pointers
@property (nonatomic, assign) DalaBLEDeviceFoundCallback deviceFoundCallback;
@property (nonatomic, assign) DalaBLEDeviceConnectedCallback deviceConnectedCallback;
@property (nonatomic, assign) DalaBLEDeviceConnectFailedCallback deviceConnectFailedCallback;
@property (nonatomic, assign) DalaBLEDeviceDisconnectedCallback deviceDisconnectedCallback;
@property (nonatomic, assign) DalaBLEServicesDiscoveredCallback servicesDiscoveredCallback;
@property (nonatomic, assign) DalaBLECharacteristicReadCallback characteristicReadCallback;
@property (nonatomic, assign) DalaBLECharacteristicWrittenCallback characteristicWrittenCallback;
@property (nonatomic, assign) DalaBLECharacteristicNotifiedCallback characteristicNotifiedCallback;

@end

@implementation DalaBluetoothManager

+ (instancetype)sharedManager {
    static DalaBluetoothManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[DalaBluetoothManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        _bleQueue = dispatch_queue_create("com.dala.bluetooth", DISPATCH_QUEUE_SERIAL);
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:_bleQueue];
        _discoveredDevices = [NSMutableDictionary dictionary];
        _connectedPeripherals = [NSMutableDictionary dictionary];
        _scanning = NO;
        _deviceFoundCallback = NULL;
        _deviceConnectedCallback = NULL;
        _deviceConnectFailedCallback = NULL;
        _deviceDisconnectedCallback = NULL;
        _servicesDiscoveredCallback = NULL;
        _characteristicReadCallback = NULL;
        _characteristicWrittenCallback = NULL;
        _characteristicNotifiedCallback = NULL;
    }
    return self;
}

// Set callbacks (called from Rust)
- (void)setDeviceFoundCallback:(DalaBLEDeviceFoundCallback)callback {
    self.deviceFoundCallback = callback;
}

- (void)setDeviceConnectedCallback:(DalaBLEDeviceConnectedCallback)callback {
    self.deviceConnectedCallback = callback;
}

- (void)setDeviceConnectFailedCallback:(DalaBLEDeviceConnectFailedCallback)callback {
    self.deviceConnectFailedCallback = callback;
}

- (void)setDeviceDisconnectedCallback:(DalaBLEDeviceDisconnectedCallback)callback {
    self.deviceDisconnectedCallback = callback;
}

- (void)setServicesDiscoveredCallback:(DalaBLEServicesDiscoveredCallback)callback {
    self.servicesDiscoveredCallback = callback;
}

- (void)setCharacteristicReadCallback:(DalaBLECharacteristicReadCallback)callback {
    self.characteristicReadCallback = callback;
}

- (void)setCharacteristicWrittenCallback:(DalaBLECharacteristicWrittenCallback)callback {
    self.characteristicWrittenCallback = callback;
}

- (void)setCharacteristicNotifiedCallback:(DalaBLECharacteristicNotifiedCallback)callback {
    self.characteristicNotifiedCallback = callback;
}

#pragma mark - State

- (NSString *)bluetoothState {
    if (!self.centralManager) {
        return @"unsupported";
    }

    switch (self.centralManager.state) {
        case CBManagerStatePoweredOn:
            return @"powered_on";
        case CBManagerStatePoweredOff:
            return @"powered_off";
        case CBManagerStateResetting:
            return @"resetting";
        case CBManagerStateUnauthorized:
            return @"unauthorized";
        case CBManagerStateUnknown:
            return @"unknown";
        case CBManagerStateUnsupported:
            return @"unsupported";
        default:
            return @"unknown";
    }
}

#pragma mark - Scanning

- (void)startScanWithServices:(NSArray<NSString *> *)serviceUUIDs timeoutMs:(NSUInteger)timeoutMs {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        NSLog(@"[Dala BLE] Cannot scan: Bluetooth not powered on (state: %@)", [self bluetoothState]);
        return;
    }

    [self.discoveredDevices removeAllObjects];

    NSMutableArray *uuids = nil;
    if (serviceUUIDs && serviceUUIDs.count > 0) {
        uuids = [NSMutableArray array];
        for (NSString *uuidStr in serviceUUIDs) {
            CBUUID *uuid = [CBUUID UUIDWithString:uuidStr];
            if (uuid) {
                [uuids addObject:uuid];
            }
        }
    }

    NSLog(@"[Dala BLE] Starting scan for services: %@", uuids);
    [self.centralManager scanForPeripheralsWithServices:uuids options:@{
        CBCentralManagerScanOptionAllowDuplicatesKey: @NO
    }];
    self.scanning = YES;

    if (timeoutMs > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutMs * NSEC_PER_MSEC)), self.bleQueue, ^{
            if (self.scanning) {
                NSLog(@"[Dala BLE] Scan timeout, stopping");
                [self stopScan];
            }
        });
    }
}

- (void)stopScan {
    if (self.scanning) {
        NSLog(@"[Dala BLE] Stopping scan");
        [self.centralManager stopScan];
        self.scanning = NO;
    }
}

- (BOOL)isScanning {
    return self.scanning;
}

#pragma mark - Connection

- (void)connectDeviceWithIdentifier:(NSString *)identifier {
    DalaBluetoothDevice *device = self.discoveredDevices[identifier];
    if (!device || !device.peripheral) {
        NSLog(@"[Dala BLE] Cannot connect: device not found for identifier %@", identifier);
        return;
    }

    NSLog(@"[Dala BLE] Connecting to %@", identifier);
    [self.centralManager connectPeripheral:device.peripheral options:nil];
}

- (void)disconnectDeviceWithIdentifier:(NSString *)identifier {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (peripheral) {
        NSLog(@"[Dala BLE] Disconnecting from %@", identifier);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}

- (BOOL)isDeviceConnected:(NSString *)identifier {
    return self.connectedPeripherals[identifier] != nil;
}

#pragma mark - Services

- (void)discoverServicesForDevice:(NSString *)identifier {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (!peripheral) {
        NSLog(@"[Dala BLE] Cannot discover services: device not connected %@", identifier);
        return;
    }

    NSLog(@"[Dala BLE] Discovering services for %@", identifier);
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

#pragma mark - Characteristics

- (CBCharacteristic *)findCharacteristic:(NSString *)characteristicUUID
                                service:(NSString *)serviceUUID
                              peripheral:(CBPeripheral *)peripheral {
    for (CBService *service in peripheral.services) {
        if ([service.UUID.UUIDString isEqualToString:serviceUUID] ||
            [service.UUID.UUIDString.lowercaseString isEqualToString:serviceUUID.lowercaseString]) {
            for (CBCharacteristic *characteristic in service.characteristics) {
                if ([characteristic.UUID.UUIDString isEqualToString:characteristicUUID] ||
                    [characteristic.UUID.UUIDString.lowercaseString isEqualToString:characteristicUUID.lowercaseString]) {
                    return characteristic;
                }
            }
        }
    }
    return nil;
}

- (void)readCharacteristic:(NSString *)characteristicUUID
                forService:(NSString *)serviceUUID
                  deviceId:(NSString *)identifier {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (!peripheral) {
        NSLog(@"[Dala BLE] Cannot read: device not connected %@", identifier);
        return;
    }

    CBCharacteristic *characteristic = [self findCharacteristic:characteristicUUID
                                                      service:serviceUUID
                                                    peripheral:peripheral];
    if (!characteristic) {
        NSLog(@"[Dala BLE] Cannot read: characteristic not found %@ for service %@", characteristicUUID, serviceUUID);
        return;
    }

    NSLog(@"[Dala BLE] Reading characteristic %@ for device %@", characteristicUUID, identifier);
    [peripheral readValueForCharacteristic:characteristic];
}

- (void)writeCharacteristic:(NSString *)characteristicUUID
                  forService:(NSString *)serviceUUID
                    deviceId:(NSString *)identifier
                       value:(NSData *)data {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (!peripheral) {
        NSLog(@"[Dala BLE] Cannot write: device not connected %@", identifier);
        return;
    }

    CBCharacteristic *characteristic = [self findCharacteristic:characteristicUUID
                                                      service:serviceUUID
                                                    peripheral:peripheral];
    if (!characteristic) {
        NSLog(@"[Dala BLE] Cannot write: characteristic not found %@ for service %@", characteristicUUID, serviceUUID);
        return;
    }

    NSLog(@"[Dala BLE] Writing %lu bytes to characteristic %@ for device %@", (unsigned long)data.length, characteristicUUID, identifier);
    [peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
}

- (void)subscribeToCharacteristic:(NSString *)characteristicUUID
                        forService:(NSString *)serviceUUID
                          deviceId:(NSString *)identifier {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (!peripheral) {
        NSLog(@"[Dala BLE] Cannot subscribe: device not connected %@", identifier);
        return;
    }

    CBCharacteristic *characteristic = [self findCharacteristic:characteristicUUID
                                                      service:serviceUUID
                                                    peripheral:peripheral];
    if (!characteristic) {
        NSLog(@"[Dala BLE] Cannot subscribe: characteristic not found %@ for service %@", characteristicUUID, serviceUUID);
        return;
    }

    NSLog(@"[Dala BLE] Subscribing to characteristic %@ for device %@", characteristicUUID, identifier);
    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
}

- (void)unsubscribeFromCharacteristic:(NSString *)characteristicUUID
                            forService:(NSString *)serviceUUID
                              deviceId:(NSString *)identifier {
    CBPeripheral *peripheral = self.connectedPeripherals[identifier];
    if (!peripheral) {
        NSLog(@"[Dala BLE] Cannot unsubscribe: device not connected %@", identifier);
        return;
    }

    CBCharacteristic *characteristic = [self findCharacteristic:characteristicUUID
                                                      service:serviceUUID
                                                    peripheral:peripheral];
    if (!characteristic) {
        NSLog(@"[Dala BLE] Cannot unsubscribe: characteristic not found %@ for service %@", characteristicUUID, serviceUUID);
        return;
    }

    NSLog(@"[Dala BLE] Unsubscribing from characteristic %@ for device %@", characteristicUUID, identifier);
    [peripheral setNotifyValue:NO forCharacteristic:characteristic];
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSLog(@"[Dala BLE] Central manager state updated: %ld", (long)central.state);
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *,id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {

    NSString *identifier = peripheral.identifier.UUIDString;
    NSString *name = peripheral.name ?: @"Unknown";

    NSLog(@"[Dala BLE] Discovered peripheral: %@ (%@), RSSI: %@", name, identifier, RSSI);

    DalaBluetoothDevice *device = [[DalaBluetoothDevice alloc] init];
    device.identifier = identifier;
    device.name = name;
    device.rssi = RSSI;
    device.advertisementData = advertisementData;
    device.peripheral = peripheral;

    self.discoveredDevices[identifier] = device;

    // Notify Rust/NIF - device found
    if (self.deviceFoundCallback) {
        NSString *advDataStr = [self serializeAdvertisementData:advertisementData];
        self.deviceFoundCallback(identifier.UTF8String, name.UTF8String, RSSI.intValue, advDataStr.UTF8String);
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSString *identifier = peripheral.identifier.UUIDString;
    NSLog(@"[Dala BLE] Connected to peripheral: %@", identifier);

    self.connectedPeripherals[identifier] = peripheral;
    peripheral.delegate = self;

    if (self.deviceConnectedCallback) {
        self.deviceConnectedCallback(identifier.UTF8String);
    }
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;
    NSLog(@"[Dala BLE] Failed to connect to peripheral: %@, error: %@", identifier, error);

    if (self.deviceConnectFailedCallback) {
        self.deviceConnectFailedCallback(identifier.UTF8String, error.localizedDescription ? error.localizedDescription.UTF8String : "Unknown error");
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;
    NSLog(@"[Dala BLE] Disconnected from peripheral: %@, error: %@", identifier, error);

    [self.connectedPeripherals removeObjectForKey:identifier];

    if (self.deviceDisconnectedCallback) {
        self.deviceDisconnectedCallback(identifier.UTF8String);
    }
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;

    if (error) {
        NSLog(@"[Dala BLE] Error discovering services for %@: %@", identifier, error);
        if (self.servicesDiscoveredCallback) {
            self.servicesDiscoveredCallback(identifier.UTF8String, nil, error.localizedDescription ? error.localizedDescription.UTF8String : @"Unknown error");
        }
        return;
    }

    NSLog(@"[Dala BLE] Discovered %lu services for %@", (unsigned long)peripheral.services.count, identifier);

    NSMutableArray *serviceUUIDs = [NSMutableArray array];
    for (CBService *service in peripheral.services) {
        [serviceUUIDs addObject:service.UUID.UUIDString];
        // Discover characteristics for each service
        [peripheral discoverCharacteristics:nil forService:service];
    }

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:serviceUUIDs options:0 error:&jsonError];
    NSString *servicesJSON = nil;
    if (jsonData && !jsonError) {
        servicesJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    if (self.servicesDiscoveredCallback) {
        self.servicesDiscoveredCallback(identifier.UTF8String, servicesJSON.UTF8String, nil);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;

    if (error) {
        NSLog(@"[Dala BLE] Error discovering characteristics for service %@ on %@: %@", service.UUID.UUIDString, identifier, error);
        return;
    }

    NSLog(@"[Dala BLE] Discovered %lu characteristics for service %@ on %@", (unsigned long)service.characteristics.count, service.UUID.UUIDString, identifier);
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;

    if (error) {
        NSLog(@"[Dala BLE] Error reading characteristic %@ for %@: %@", characteristic.UUID.UUIDString, identifier, error);
        if (self.characteristicReadCallback) {
            self.characteristicReadCallback(identifier.UTF8String, characteristic.service.UUID.UUIDString.UTF8String, characteristic.UUID.UUIDString.UTF8String, nil, 0, error.localizedDescription ? error.localizedDescription.UTF8String : @"Unknown error");
        }
        return;
    }

    NSData *value = characteristic.value;
    NSLog(@"[Dala BLE] Read characteristic %@ for %@: %lu bytes", characteristic.UUID.UUIDString, identifier, (unsigned long)value.length);

    if (self.characteristicReadCallback) {
        self.characteristicReadCallback(identifier.UTF8String, characteristic.service.UUID.UUIDString.UTF8String, characteristic.UUID.UUIDString.UTF8String, (const uint8_t *)value.bytes, value.length, nil);
    }

    // Also handle notifications
    if (characteristic.isNotifying) {
        if (self.characteristicNotifiedCallback) {
            self.characteristicNotifiedCallback(identifier.UTF8String, characteristic.service.UUID.UUIDString.UTF8String, characteristic.UUID.UUIDString.UTF8String, (const uint8_t *)value.bytes, value.length);
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;

    if (error) {
        NSLog(@"[Dala BLE] Error writing characteristic %@ for %@: %@", characteristic.UUID.UUIDString, identifier, error);
        if (self.characteristicWrittenCallback) {
            self.characteristicWrittenCallback(identifier.UTF8String, characteristic.service.UUID.UUIDString.UTF8String, characteristic.UUID.UUIDString.UTF8String, error.localizedDescription ? error.localizedDescription.UTF8String : @"Unknown error");
        }
        return;
    }

    NSLog(@"[Dala BLE] Successfully wrote characteristic %@ for %@", characteristic.UUID.UUIDString, identifier);

    if (self.characteristicWrittenCallback) {
        self.characteristicWrittenCallback(identifier.UTF8String, characteristic.service.UUID.UUIDString.UTF8String, characteristic.UUID.UUIDString.UTF8String, nil);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSString *identifier = peripheral.identifier.UUIDString;

    if (error) {
        NSLog(@"[Dala BLE] Error updating notification state for characteristic %@ for %@: %@", characteristic.UUID.UUIDString, identifier, error);
        return;
    }

    NSLog(@"[Dala BLE] Notification state updated for characteristic %@ for %@: %@", characteristic.UUID.UUIDString, identifier, characteristic.isNotifying ? @"subscribed" : @"unsubscribed");
}


// Helper method to serialize advertisement data
- (NSString *)serializeAdvertisementData:(NSDictionary<NSString *, id> *)advertisementData {
    if (!advertisementData) return @"{}";
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:advertisementData options:0 error:&error];
    if (jsonData && !error) {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return @"{}";
}

@end
