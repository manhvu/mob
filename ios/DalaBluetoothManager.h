// DalaBluetoothManager.h - iOS CoreBluetooth wrapper for Dala
// Provides BLE functionality via Objective-C to be called from Rust

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@interface DalaBluetoothDevice : NSObject

@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSNumber *rssi;
@property (nonatomic, strong) NSDictionary<NSString *, id> *advertisementData;
@property (nonatomic, strong) CBPeripheral *peripheral;

@end

// Callback types
typedef void (*DalaBLEDeviceFoundCallback)(const char *identifier, const char *name, int rssi, const char *advertisementData);
typedef void (*DalaBLEDeviceConnectedCallback)(const char *identifier);
typedef void (*DalaBLEDeviceConnectFailedCallback)(const char *identifier, const char *error);
typedef void (*DalaBLEDeviceDisconnectedCallback)(const char *identifier);
typedef void (*DalaBLEServicesDiscoveredCallback)(const char *identifier, const char *servicesJSON, const char *error);
typedef void (*DalaBLECharacteristicReadCallback)(const char *identifier, const char *service, const char *characteristic, const uint8_t *value, size_t valueLen, const char *error);
typedef void (*DalaBLECharacteristicWrittenCallback)(const char *identifier, const char *service, const char *characteristic, const char *error);
typedef void (*DalaBLECharacteristicNotifiedCallback)(const char *identifier, const char *service, const char *characteristic, const uint8_t *value, size_t valueLen);

@interface DalaBluetoothManager : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>

+ (instancetype)sharedManager;

// Set callbacks (called from Rust)
- (void)setDeviceFoundCallback:(DalaBLEDeviceFoundCallback)callback;
- (void)setDeviceConnectedCallback:(DalaBLEDeviceConnectedCallback)callback;
- (void)setDeviceConnectFailedCallback:(DalaBLEDeviceConnectFailedCallback)callback;
- (void)setDeviceDisconnectedCallback:(DalaBLEDeviceDisconnectedCallback)callback;
- (void)setServicesDiscoveredCallback:(DalaBLEServicesDiscoveredCallback)callback;
- (void)setCharacteristicReadCallback:(DalaBLECharacteristicReadCallback)callback;
- (void)setCharacteristicWrittenCallback:(DalaBLECharacteristicWrittenCallback)callback;
- (void)setCharacteristicNotifiedCallback:(DalaBLECharacteristicNotifiedCallback)callback;

// State
- (NSString *)bluetoothState;

// Scanning
- (void)startScanWithServices:(NSArray<NSString *> * _Nullable)serviceUUIDs timeoutMs:(NSUInteger)timeoutMs;
- (void)stopScan;
- (BOOL)isScanning;

// Connection
- (void)connectDeviceWithIdentifier:(NSString *)identifier;
- (void)disconnectDeviceWithIdentifier:(NSString *)identifier;
- (BOOL)isDeviceConnected:(NSString *)identifier;

// Services
- (void)discoverServicesForDevice:(NSString *)identifier;

// Characteristics
- (void)readCharacteristic:(NSString *)characteristicUUID
                forService:(NSString *)serviceUUID
                  deviceId:(NSString *)identifier;

- (void)writeCharacteristic:(NSString *)characteristicUUID
                  forService:(NSString *)serviceUUID
                    deviceId:(NSString *)identifier
                       value:(NSData *)data;

- (void)subscribeToCharacteristic:(NSString *)characteristicUUID
                        forService:(NSString *)serviceUUID
                          deviceId:(NSString *)identifier;

- (void)unsubscribeFromCharacteristic:(NSString *)characteristicUUID
                            forService:(NSString *)serviceUUID
                              deviceId:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
