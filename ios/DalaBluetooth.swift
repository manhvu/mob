// DalaBluetooth.swift - Swift wrapper to ensure DalaBluetoothManager is linked

import CoreBluetooth
import Foundation

@objc class DalaBluetoothBridge: NSObject {
    @objc static func ensureLinked() {
        // This function ensures the DalaBluetoothManager is linked into the binary
        let _ = DalaBluetoothManager.sharedManager
    }
}
