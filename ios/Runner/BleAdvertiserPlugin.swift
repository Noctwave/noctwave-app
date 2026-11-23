import CoreBluetooth
import Flutter
import UIKit

/**
 * Нативный BLE-рекламщик iOS (ТЗ 5.3).
 *
 * CoreBluetooth запрещает ManufacturerData сторонним приложениям, поэтому
 * 11-байтовый пейлоад упаковывается в шесть 16-битных Service UUID с
 * XOR pre-whitening. В startAdvertising передаётся ТОЛЬКО
 * CBAdvertisementDataServiceUUIDsKey (ровно 6 элементов, Array, не Set).
 */
class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
    static let channelName = "com.pulselocal/ble_advertiser"
    static let xorMask: [UInt8] = [0x94, 0xBE, 0x0A, 0xED, 0x39, 0x35, 0x83, 0xAD, 0x8B, 0x89, 0x40]
    static let terminator: UInt8 = 0x0B

    private var channel: FlutterMethodChannel?
    private var manager: CBPeripheralManager?
    private var burstTimer: Timer?
    private var pendingResult: FlutterResult?
    private var pendingPayload: [CBUUID]?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = BleAdvertiserPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getBluetoothState":
            result(bluetoothState())
        case "broadcastCommand", "broadcastStop":
            let args = call.arguments as? [String: Any] ?? [:]
            let prefix = args["prefixHex"] as? String ?? ""
            let commandKey = call.method == "broadcastStop" ? "stopHex" : "commandHex"
            let command = args[commandKey] as? String ?? ""
            let durationMs = args["durationMs"] as? Int ?? 350
            broadcast(prefixHex: prefix, commandHex: command, durationMs: durationMs, result: result)
        case "stopAdvertising":
            stopAdvertising()
            result(nil)
        case "previewEncodedPacket":
            let args = call.arguments as? [String: Any] ?? [:]
            let prefix = args["prefixHex"] as? String ?? ""
            let command = args["commandHex"] as? String ?? ""
            let uuids = encodeUuids(prefixHex: prefix, commandHex: command)
            result([
                "platform": "ios",
                "iosServiceUuids": uuids.map { $0.uuidString }
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Кодирование (ТЗ 5.3)

    static func hexToBytes(_ hex: String) -> [UInt8] {
        let clean = hex.filter { $0.isHexDigit }
        var bytes: [UInt8] = []
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            if let byte = UInt8(clean[idx..<next], radix: 16) {
                bytes.append(byte)
            }
            idx = next
        }
        return bytes
    }

    /// raw[11] → XOR mask[11] → +0x0B → 12 байт → 6 пар LE → 6 CBUUID.
    func encodeUuids(prefixHex: String, commandHex: String) -> [CBUUID] {
        let raw = BleAdvertiserPlugin.hexToBytes(prefixHex) + BleAdvertiserPlugin.hexToBytes(commandHex)
        guard raw.count == 11 else { return [] }
        var encoded = [UInt8](repeating: 0, count: 12)
        for k in 0..<11 {
            encoded[k] = raw[k] ^ BleAdvertiserPlugin.xorMask[k]
        }
        encoded[11] = BleAdvertiserPlugin.terminator
        var uuids: [CBUUID] = []
        for j in 0..<6 {
            let lo = encoded[j * 2]
            let hi = encoded[j * 2 + 1]
            let str = String(format: "%02X%02X", hi, lo)
            uuids.append(CBUUID(string: str))
        }
        return uuids
    }

    // MARK: - Реклама

    private func bluetoothState() -> String {
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }
        guard let m = manager else { return "unsupported" }
        switch m.state {
        case .poweredOn:
            if #available(iOS 13.1, *) {
                return m.authorization == .allowedAlways ? "ready" : "unauthorized"
            }
            return "ready"
        case .poweredOff:
            return "poweredOff"
        case .unauthorized:
            return "unauthorized"
        case .unsupported:
            return "unsupported"
        default:
            return "unknown"
        }
    }

    private func broadcast(prefixHex: String, commandHex: String, durationMs: Int, result: @escaping FlutterResult) {
        stopAdvertising()
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }
        let uuids = encodeUuids(prefixHex: prefixHex, commandHex: commandHex)
        guard uuids.count == 6 else {
            result(FlutterError(code: "ENCODE_FAILED", message: "Пейлоад не 11 байт", details: nil))
            return
        }
        pendingPayload = uuids
        pendingResult = result

        if manager?.state == .poweredOn {
            startWithCurrentPayload(durationMs: durationMs)
        }
        // Иначе ждём peripheralManagerDidUpdateState.
    }

    private func startWithCurrentPayload(durationMs: Int) {
        guard let uuids = pendingPayload, let m = manager, m.state == .poweredOn else { return }
        // ТОЛЬКО ServiceUUIDsKey. Никаких LocalName/других ключей (ТЗ 5.3).
        let data: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: uuids]
        m.startAdvertising(data)
        pendingResult?(nil)
        pendingResult = nil
        if durationMs > 0 {
            burstTimer = Timer.scheduledTimer(withTimeInterval: Double(durationMs) / 1000.0, repeats: false) { [weak self] _ in
                self?.stopAdvertising()
            }
        }
    }

    private func stopAdvertising() {
        burstTimer?.invalidate()
        burstTimer = nil
        manager?.stopAdvertising()
        pendingPayload = nil
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, pendingPayload != nil {
            startWithCurrentPayload(durationMs: 0)
        } else if peripheral.state != .poweredOn, let r = pendingResult {
            r(FlutterError(code: "BT_UNAVAILABLE", message: "Bluetooth недоступен: \(peripheral.state.rawValue)", details: nil))
            pendingResult = nil
            pendingPayload = nil
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error, let r = pendingResult {
            r(FlutterError(code: "ADVERTISE_FAILED", message: error.localizedDescription, details: nil))
            pendingResult = nil
        }
    }
}
