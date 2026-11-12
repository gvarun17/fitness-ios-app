import Foundation
import CoreBluetooth
import RunCore

/// Connects to a Bluetooth heart rate sensor (chest strap, or a watch broadcasting
/// heart rate) using the standard Heart Rate profile, and remembers it between launches.
final class HeartRateMonitor: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = HeartRateMonitor()

    enum Status: Equatable {
        /// Bluetooth hasn't been started (no sensor paired yet).
        case idle
        case bluetoothOff
        case unauthorized
        /// Bluetooth is on; no sensor is paired.
        case ready
        /// A paired sensor is being looked for. Stays here until it comes into range.
        case connecting
        case connected
    }

    struct FoundSensor: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
    }

    @Published private(set) var status: Status = .idle
    /// Latest beats per minute, nil when not connected or the sensor has no reading.
    @Published private(set) var heartRate: Double?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var found: [FoundSensor] = []
    @Published private(set) var isScanning = false
    @Published private(set) var pairedName: String?
    /// When the last reading arrived, used to spot a silent sensor.
    private(set) var lastReading: Date?

    private static let pairedIDKey = "heartRateSensorID"
    private static let pairedNameKey = "heartRateSensorName"
    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var wantsScan = false

    private override init() {
        super.init()
        pairedName = UserDefaults.standard.string(forKey: Self.pairedNameKey)
    }

    private var pairedID: UUID? {
        UserDefaults.standard.string(forKey: Self.pairedIDKey).flatMap(UUID.init(uuidString:))
    }

    var hasPairedSensor: Bool { pairedID != nil }

    // MARK: Control

    /// Starts Bluetooth. The first call shows the system Bluetooth permission prompt.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Starts Bluetooth only if a sensor was paired before, so runners without one are never prompted.
    func activateIfPaired() {
        if hasPairedSensor { activate() }
    }

    func startScan() {
        activate()
        wantsScan = true
        found = []
        discovered = [:]
        beginScanIfPossible()
    }

    func stopScan() {
        wantsScan = false
        isScanning = false
        central?.stopScan()
    }

    func connect(_ sensor: FoundSensor) {
        guard let central, let target = discovered[sensor.id] else { return }
        stopScan()
        if let current = peripheral, current.identifier != target.identifier {
            central.cancelPeripheralConnection(current)
        }
        UserDefaults.standard.set(sensor.id.uuidString, forKey: Self.pairedIDKey)
        UserDefaults.standard.set(sensor.name, forKey: Self.pairedNameKey)
        pairedName = sensor.name
        attach(target)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.pairedIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pairedNameKey)
        pairedName = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        heartRate = nil
        batteryLevel = nil
        if central?.state == .poweredOn { status = .ready }
    }

    private func beginScanIfPossible() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
    }

    private func attach(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        status = .connecting
        // No timeout: the request stays pending until the sensor is in range and awake.
        central?.connect(target, options: nil)
    }

    private func reconnectPaired() {
        guard let central, central.state == .poweredOn, let id = pairedID else { return }
        if let current = peripheral, current.identifier == id, current.state == .connected { return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(known)
        } else {
            status = .ready
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .ready
            reconnectPaired()
            beginScanIfPossible()
        case .unauthorized:
            status = .unauthorized
            heartRate = nil
        case .poweredOff, .resetting, .unsupported, .unknown:
            status = .bluetoothOff
            heartRate = nil
            isScanning = false
        @unknown default:
            status = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised ?? "Heart rate sensor"
        discovered[peripheral.identifier] = peripheral
        let sensor = FoundSensor(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = found.firstIndex(where: { $0.id == sensor.id }) {
            found[index] = sensor
        } else {
            found.append(sensor)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .connected
        if let name = peripheral.name, !name.isEmpty {
            pairedName = name
            UserDefaults.standard.set(name, forKey: Self.pairedNameKey)
        }
        peripheral.discoverServices([Self.heartRateService, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handleDisconnect(of: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDisconnect(of: peripheral)
    }

    private func handleDisconnect(of lost: CBPeripheral) {
        guard lost.identifier == peripheral?.identifier else { return }
        heartRate = nil
        // Keep trying for as long as the sensor stays paired.
        if pairedID == lost.identifier, central?.state == .poweredOn {
            attach(lost)
        } else {
            peripheral = nil
            if central?.state == .poweredOn { status = .ready }
        }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == Self.heartRateService {
                peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
            } else if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.heartRateMeasurement {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == Self.batteryLevelCharacteristic {
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == Self.heartRateMeasurement {
            guard let reading = HeartRateReading.parse([UInt8](data)) else { return }
            lastReading = Date()
            heartRate = reading.bpm
        } else if characteristic.uuid == Self.batteryLevelCharacteristic, let level = data.first {
            batteryLevel = Int(level)
        }
    }
}
