package com.example.dala;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.net.wifi.ScanResult;
import android.content.BroadcastReceiver;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * DalaBridge - Java bridge class for Dala framework Android integration.
 * Handles Bluetooth Low Energy (BLE) operations and other native functionality.
 */
public class DalaBridge {
    private static final String TAG = "DalaBridge";

    private static Context appContext;
    private static BluetoothManager bluetoothManager;
    private static BluetoothAdapter bluetoothAdapter;
    private static BluetoothLeScanner bleScanner;
    private static Handler mainHandler;

    // Store GATT connections by device ID (MAC address)
    private static Map<String, BluetoothGatt> gattConnections = new HashMap<>();

    // Scan callback
    private static ScanCallback scanCallback;
    private static boolean isScanning = false;

    // Native function declarations (implemented in Rust NIF)
    private static native void nativeBluetoothDeviceFound(String deviceId, String name, int rssi);
    private static native void nativeBluetoothStateChanged(String state);
    private static native void nativeBluetoothConnected(String deviceId);
    private static native void nativeBluetoothDisconnected(String deviceId);
    private static native void nativeBluetoothServicesDiscovered(String deviceId, String servicesJson);
    private static native void nativeBluetoothCharacteristicRead(String deviceId, String service, String characteristic, byte[] value);
    private static native void nativeBluetoothCharacteristicWritten(String deviceId, String service, String characteristic);
    private static native void nativeBluetoothNotificationReceived(String deviceId, String service, String characteristic, byte[] value);

    /**
     * Initialize the bridge with application context.
     * Call this from your main activity or application class.
     */
    public static void init(Context context) {
        appContext = context.getApplicationContext();
        bluetoothManager = (BluetoothManager) appContext.getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
        }
        mainHandler = new Handler(Looper.getMainLooper());
        Log.i(TAG, "DalaBridge initialized");
    }

    // ========================================================================
    // Bluetooth State
    // ========================================================================

    public static String bluetoothGetState() {
        if (bluetoothAdapter == null) {
            return "unsupported";
        }
        int state = bluetoothAdapter.getState();
        switch (state) {
            case BluetoothAdapter.STATE_OFF:
                return "powered_off";
            case BluetoothAdapter.STATE_TURNING_ON:
                return "turning_on";
            case BluetoothAdapter.STATE_ON:
                return "powered_on";
            case BluetoothAdapter.STATE_TURNING_OFF:
                return "turning_off";
            default:
                return "unknown";
        }
    }

    // ========================================================================
    // BLE Scanning
    // ========================================================================

    public static void bluetoothStartScan(List<String> serviceUuids, long timeoutMs) {
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            Log.e(TAG, "Bluetooth not available or not enabled");
            return;
        }

        bleScanner = bluetoothAdapter.getBluetoothLeScanner();
        if (bleScanner == null) {
            Log.e(TAG, "BluetoothLeScanner not available");
            return;
        }

        // Build scan filters from service UUIDs
        List<ScanFilter> filters = new ArrayList<>();
        if (serviceUuids != null && !serviceUuids.isEmpty()) {
            for (String uuid : serviceUuids) {
                try {
                    ScanFilter filter = new ScanFilter.Builder()
                            .setServiceUuid(new ParcelUuid(UUID.fromString(uuid)))
                            .build();
                    filters.add(filter);
                } catch (IllegalArgumentException e) {
                    Log.e(TAG, "Invalid UUID: " + uuid, e);
                }
            }
        }

        // Scan settings
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();

        // Create scan callback
        scanCallback = new ScanCallback() {
            @Override
            public void onScanResult(int callbackType, ScanResult result) {
                BluetoothDevice device = result.getDevice();
                String deviceId = device.getAddress();
                String name = device.getName();
                int rssi = result.getRssi();

                Log.d(TAG, "Device found: " + deviceId + " (" + name + "), RSSI: " + rssi);
                nativeBluetoothDeviceFound(deviceId, name != null ? name : "", rssi);
            }

            @Override
            public void onScanFailed(int errorCode) {
                Log.e(TAG, "Scan failed with error code: " + errorCode);
                isScanning = false;
            }
        };

        // Start scan
        try {
            bleScanner.startScan(filters, settings, scanCallback);
            isScanning = true;
            Log.i(TAG, "BLE scan started");

            // Stop scan after timeout
            if (timeoutMs > 0) {
                mainHandler.postDelayed(() -> {
                    bluetoothStopScan();
                }, timeoutMs);
            }
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for BLE scan", e);
        }
    }

    public static void bluetoothStopScan() {
        if (bleScanner == null || scanCallback == null || !isScanning) {
            return;
        }

        try {
            bleScanner.stopScan(scanCallback);
            isScanning = false;
            Log.i(TAG, "BLE scan stopped");
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for stopping BLE scan", e);
        }
    }

    // ========================================================================
    // GATT Connection
    // ========================================================================

    public static void bluetoothConnect(String deviceId) {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth not available");
            return;
        }

        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(deviceId);
        if (device == null) {
            Log.e(TAG, "Device not found: " + deviceId);
            return;
        }

        // Create GATT callback
        BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
            @Override
            public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
                String devId = gatt.getDevice().getAddress();
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.i(TAG, "Connected to " + devId);
                    gattConnections.put(devId, gatt);
                    nativeBluetoothConnected(devId);

                    // Discover services
                    gatt.discoverServices();
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.i(TAG, "Disconnected from " + devId);
                    gattConnections.remove(devId);
                    gatt.close();
                    nativeBluetoothDisconnected(devId);
                }
            }

            @Override
            public void onServicesDiscovered(BluetoothGatt gatt, int status) {
                String devId = gatt.getDevice().getAddress();
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.i(TAG, "Services discovered for " + devId);
                    // Build services JSON
                    StringBuilder json = new StringBuilder("[");
                    List<BluetoothGattService> services = gatt.getServices();
                    for (int i = 0; i < services.size(); i++) {
                        BluetoothGattService service = services.get(i);
                        if (i > 0) json.append(",");
                        json.append("\"").append(service.getUuid().toString()).append("\"");
                    }
                    json.append("]");
                    nativeBluetoothServicesDiscovered(devId, json.toString());
                } else {
                    Log.e(TAG, "Service discovery failed for " + devId + ", status: " + status);
                }
            }

            @Override
            public void onCharacteristicRead(BluetoothGatt gatt,
                                             BluetoothGattCharacteristic characteristic,
                                             int status) {
                String devId = gatt.getDevice().getAddress();
                UUID serviceUuid = characteristic.getService().getUuid();
                UUID charUuid = characteristic.getUuid();
                byte[] value = characteristic.getValue();

                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "Characteristic read: " + charUuid);
                    nativeBluetoothCharacteristicRead(devId, serviceUuid.toString(),
                                                     charUuid.toString(), value);
                } else {
                    Log.e(TAG, "Characteristic read failed: " + charUuid + ", status: " + status);
                }
            }

            @Override
            public void onCharacteristicWrite(BluetoothGatt gatt,
                                              BluetoothGattCharacteristic characteristic,
                                              int status) {
                String devId = gatt.getDevice().getAddress();
                UUID serviceUuid = characteristic.getService().getUuid();
                UUID charUuid = characteristic.getUuid();

                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "Characteristic written: " + charUuid);
                    nativeBluetoothCharacteristicWritten(devId, serviceUuid.toString(),
                                                        charUuid.toString());
                } else {
                    Log.e(TAG, "Characteristic write failed: " + charUuid + ", status: " + status);
                }
            }

            @Override
            public void onCharacteristicChanged(BluetoothGatt gatt,
                                               BluetoothGattCharacteristic characteristic) {
                String devId = gatt.getDevice().getAddress();
                UUID serviceUuid = characteristic.getService().getUuid();
                UUID charUuid = characteristic.getUuid();
                byte[] value = characteristic.getValue();

                Log.d(TAG, "Notification received: " + charUuid);
                nativeBluetoothNotificationReceived(devId, serviceUuid.toString(),
                                                   charUuid.toString(), value);
            }
        };

        // Connect to GATT server
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            } else {
                device.connectGatt(appContext, false, gattCallback);
            }
            Log.i(TAG, "Connecting to " + deviceId);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for GATT connection", e);
        }
    }

    public static void bluetoothDisconnect(String deviceId) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt != null) {
            try {
                gatt.disconnect();
                Log.i(TAG, "Disconnecting from " + deviceId);
            } catch (SecurityException e) {
                Log.e(TAG, "Permission denied for disconnect", e);
            }
        }
    }

    // ========================================================================
    // GATT Operations
    // ========================================================================

    public static void bluetoothDiscoverServices(String deviceId) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt != null) {
            gatt.discoverServices();
            Log.i(TAG, "Discovering services for " + deviceId);
        } else {
            Log.e(TAG, "No GATT connection for " + deviceId);
        }
    }

    public static void bluetoothReadCharacteristic(String deviceId, String serviceUuid, String characteristicUuid) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt == null) {
            Log.e(TAG, "No GATT connection for " + deviceId);
            return;
        }

        BluetoothGattService service = gatt.getService(UUID.fromString(serviceUuid));
        if (service == null) {
            Log.e(TAG, "Service not found: " + serviceUuid);
            return;
        }

        BluetoothGattCharacteristic characteristic = service.getCharacteristic(UUID.fromString(characteristicUuid));
        if (characteristic == null) {
            Log.e(TAG, "Characteristic not found: " + characteristicUuid);
            return;
        }

        try {
            gatt.readCharacteristic(characteristic);
            Log.d(TAG, "Reading characteristic " + characteristicUuid);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for read", e);
        }
    }

    public static void bluetoothWriteCharacteristic(String deviceId, String serviceUuid,
                                                   String characteristicUuid, byte[] value) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt == null) {
            Log.e(TAG, "No GATT connection for " + deviceId);
            return;
        }

        BluetoothGattService service = gatt.getService(UUID.fromString(serviceUuid));
        if (service == null) {
            Log.e(TAG, "Service not found: " + serviceUuid);
            return;
        }

        BluetoothGattCharacteristic characteristic = service.getCharacteristic(UUID.fromString(characteristicUuid));
        if (characteristic == null) {
            Log.e(TAG, "Characteristic not found: " + characteristicUuid);
            return;
        }

        try {
            characteristic.setValue(value);
            gatt.writeCharacteristic(characteristic);
            Log.d(TAG, "Writing characteristic " + characteristicUuid);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for write", e);
        }
    }

    public static void bluetoothSubscribe(String deviceId, String serviceUuid, String characteristicUuid) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt == null) {
            Log.e(TAG, "No GATT connection for " + deviceId);
            return;
        }

        BluetoothGattService service = gatt.getService(UUID.fromString(serviceUuid));
        if (service == null) {
            Log.e(TAG, "Service not found: " + serviceUuid);
            return;
        }

        BluetoothGattCharacteristic characteristic = service.getCharacteristic(UUID.fromString(characteristicUuid));
        if (characteristic == null) {
            Log.e(TAG, "Characteristic not found: " + characteristicUuid);
            return;
        }

        try {
            // Enable notifications locally
            gatt.setCharacteristicNotification(characteristic, true);

            // Write to descriptor to enable notifications on the device
            // This is typically the Client Characteristic Configuration Descriptor (0x2902)
            BluetoothGattDescriptor descriptor = characteristic.getDescriptor(
                    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));
            if (descriptor != null) {
                descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                gatt.writeDescriptor(descriptor);
            }

            Log.d(TAG, "Subscribed to characteristic " + characteristicUuid);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for subscribe", e);
        }
    }

    public static void bluetoothUnsubscribe(String deviceId, String serviceUuid, String characteristicUuid) {
        BluetoothGatt gatt = gattConnections.get(deviceId);
        if (gatt == null) {
            Log.e(TAG, "No GATT connection for " + deviceId);
            return;
        }

        BluetoothGattService service = gatt.getService(UUID.fromString(serviceUuid));
        if (service == null) {
            Log.e(TAG, "Service not found: " + serviceUuid);
            return;
        }

        BluetoothGattCharacteristic characteristic = service.getCharacteristic(UUID.fromString(characteristicUuid));
        if (characteristic == null) {
            Log.e(TAG, "Characteristic not found: " + characteristicUuid);
            return;
        }

        try {
            gatt.setCharacteristicNotification(characteristic, false);

            BluetoothGattDescriptor descriptor = characteristic.getDescriptor(
                    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));
            if (descriptor != null) {
                descriptor.setValue(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE);
                gatt.writeDescriptor(descriptor);
            }

            Log.d(TAG, "Unsubscribed from characteristic " + characteristicUuid);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for unsubscribe", e);
        }
    }

    // ============================================================================
    // WiFi Methods
    // ============================================================================

    private static WifiManager wifiManager;
    private static BroadcastReceiver wifiScanReceiver;

    private static WifiManager getWifiManager() {
        if (wifiManager == null) {
            wifiManager = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        }
        return wifiManager;
    }

    /**
     * Get current WiFi connection info as JSON string
     * Returns: {"connected": boolean, "ssid": string, "bssid": string, "ip": string, "rssi": int}
     */
    public static String getWifiInfo() {
        WifiManager wm = getWifiManager();
        if (wm == null) {
            return "{\"connected\": false}";
        }

        try {
            WifiInfo info = wm.getConnectionInfo();
            if (info == null || info.getNetworkId() == -1) {
                return "{\"connected\": false}";
            }

            String ssid = info.getSSID();
            // SSID is often returned with quotes, remove them
            if (ssid != null && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                ssid = ssid.substring(1, ssid.length() - 1);
            }

            String bssid = info.getBSSID();
            int ip = info.getIpAddress();
            int rssi = info.getRssi();

            // Convert IP from int to string
            String ipStr = String.format("%d.%d.%d.%d",
                    (ip & 0xff),
                    ((ip >> 8) & 0xff),
                    ((ip >> 16) & 0xff),
                    ((ip >> 24) & 0xff));

            return String.format(
                    "{\"connected\": true, \"ssid\": \"%s\", \"bssid\": \"%s\", \"ip\": \"%s\", \"rssi\": %d}",
                    ssid != null ? ssid : "",
                    bssid != null ? bssid : "",
                    ipStr,
                    rssi
            );
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for getWifiInfo", e);
            return "{\"connected\": false, \"error\": \"permission_denied\"}";
        }
    }

    /**
     * Start WiFi scan
     * Requires ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION permission
     */
    public static void startWifiScan() {
        WifiManager wm = getWifiManager();
        if (wm == null) {
            Log.e(TAG, "WifiManager is null");
            return;
        }

        try {
            // Check if we have location permission (required for scan results on Android 6+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
                        != PackageManager.PERMISSION_GRANTED &&
                    context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION)
                        != PackageManager.PERMISSION_GRANTED) {
                    Log.e(TAG, "Location permission required for WiFi scan");
                    return;
                }
            }

            // Register broadcast receiver for scan results if not already registered
            if (wifiScanReceiver == null) {
                wifiScanReceiver = new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        String action = intent.getAction();
                        if (WifiManager.SCAN_RESULTS_AVAILABLE_ACTION.equals(action)) {
                            boolean success = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false);
                            if (success) {
                                List<android.net.wifi.ScanResult> results = wm.getScanResults();
                                Log.d(TAG, "WiFi scan complete, found " + results.size() + " networks");
                                // TODO: Send results back to Elixir via callback
                                // For now, just log them
                                for (android.net.wifi.ScanResult result : results) {
                                    Log.d(TAG, "  SSID: " + result.SSID + ", BSSID: " + result.BSSID + ", RSSI: " + result.level);
                                }
                            } else {
                                Log.d(TAG, "WiFi scan failed");
                            }
                        }
                    }
                };
                IntentFilter filter = new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
                context.registerReceiver(wifiScanReceiver, filter);
            }

            boolean success = wm.startScan();
            Log.d(TAG, "WiFi scan started: " + success);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for startWifiScan", e);
        }
    }

    /**
     * Enable or disable WiFi
     * Requires CHANGE_WIFI_STATE permission
     */
    public static void setWifiEnabled(boolean enabled) {
        WifiManager wm = getWifiManager();
        if (wm == null) {
            Log.e(TAG, "WifiManager is null");
            return;
        }

        try {
            boolean success = wm.setWifiEnabled(enabled);
            Log.d(TAG, "WiFi " + (enabled ? "enabled" : "disabled") + ": " + success);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for setWifiEnabled", e);
        }
    }
}
