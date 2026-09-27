import Foundation
import CoreBluetooth
import Combine

public enum BLEConnectionStatus: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected (ForeverBand)"
}

@MainActor
public final class ForeverBandBLEManager: NSObject, ObservableObject {
    @Published public var status: BLEConnectionStatus = .disconnected
    @Published public var discoveredPeripherals: [CBPeripheral] = []
    @Published public var latestVitals: VitalsReading?
    @Published public var latestEnv: EnvReading?
    @Published public var latestMotion: MotionReading?
    @Published public var rssi: Int = -60
    @Published public var isSimulationMode: Bool = false
    @Published public var lastSyncTime: Date?
    @Published public var connectedAt: Date?

    @Published public var connectingPeripheralId: UUID?
    private var centralManager: CBCentralManager!
    @Published public var connectedPeripheral: CBPeripheral?

    private var vitalsCharacteristic: CBCharacteristic?
    private var envCharacteristic: CBCharacteristic?
    private var motionCharacteristic: CBCharacteristic?
    private var timeCharacteristic: CBCharacteristic?
    private var watchSettingsCharacteristic: CBCharacteristic?

    private var simulationTimer: AnyCancellable?
    private var simTick: Double = 0.0
    private var timeSyncTimer: Timer?
    private var connectionTimeoutTimer: Timer?
    public var pendingWatchSettings: WatchSettings?
    public var onVitalsReceived: ((VitalsReading) -> Void)?
    public var onEnvReceived: ((EnvReading) -> Void)?

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning & Connection

    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredPeripherals.removeAll()
        status = .scanning
        let serviceUUID = CBUUID(string: ForeverBandProtocol.serviceUUID)
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func startScan() {
        startScanning()
    }

    public func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        connectionTimeoutTimer?.invalidate()
        connectedPeripheral = peripheral
        connectingPeripheralId = peripheral.identifier
        status = .connecting

        // 10-second timeout guard to prevent infinite connecting loop
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.status == .connecting else { return }
                self.centralManager.cancelPeripheralConnection(peripheral)
                self.status = .disconnected
                self.connectingPeripheralId = nil
                self.connectedPeripheral = nil
            }
        }

        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    public func stopScanning() {
        centralManager.stopScan()
        if status == .scanning {
            status = .disconnected
        }
    }

    public func disconnect() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        connectingPeripheralId = nil
        timeSyncTimer?.invalidate()
        timeSyncTimer = nil
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectedPeripheral = nil
        connectedAt = nil
        status = .disconnected
    }

    // MARK: - Simulation Mode (Hackathon Demo & Testing)

    public func toggleSimulationMode(_ enabled: Bool) {
        isSimulationMode = enabled
        if enabled {
            disconnect()
            status = .connected
            startSimulationStream()
        } else {
            simulationTimer?.cancel()
            simulationTimer = nil
            status = .disconnected
            startScanning()
        }
    }

    private func startSimulationStream() {
        simulationTimer?.cancel()
        simulationTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.simTick += 1.0

                // Synthetic MAX30101 Vitals
                let baseHR: Float = 74.0
                let hrDelta = sin(self.simTick * 0.15) * 4.0
                let currentHR = Float(baseHR + Float(hrDelta))
                let currentSpO2: Float = 98.5 + Float(sin(self.simTick * 0.08) * 0.8)
                let currentTemp: Float = 36.6 + Float(cos(self.simTick * 0.05) * 0.2)

                self.latestVitals = VitalsReading(
                    deviceTimeMs: UInt32(self.simTick * 1000),
                    receivedAt: Date(),
                    heartRate: currentHR,
                    spo2: currentSpO2,
                    bodyTempC: currentTemp,
                    fingerPresent: true
                )

                // Synthetic BME280 Environment
                self.latestEnv = EnvReading(
                    deviceTimeMs: UInt32(self.simTick * 1000),
                    receivedAt: Date(),
                    ambientTempC: 27.8 + Float(sin(self.simTick * 0.02) * 0.5),
                    humidity: 64.0 + Float(cos(self.simTick * 0.03) * 3.0),
                    pressureHPa: 1012.4 + Float(sin(self.simTick * 0.01) * 1.5)
                )

                // Synthetic MPU6050 Motion
                self.latestMotion = MotionReading(
                    deviceTimeMs: UInt32(self.simTick * 1000),
                    receivedAt: Date(),
                    ax: Float(sin(self.simTick * 0.5) * 0.8),
                    ay: 9.81 + Float(cos(self.simTick * 0.5) * 0.4),
                    az: Float(sin(self.simTick * 0.3) * 0.3),
                    gx: Float(cos(self.simTick) * 0.05),
                    gy: Float(sin(self.simTick) * 0.05),
                    gz: Float(cos(self.simTick * 0.5) * 0.02)
                )
            }
    }

    // MARK: - Outgoing Writes

    public func syncTimeToWatch() {
        let packet = ForeverBandProtocol.buildTimeSyncPacket(date: Date())
        if isSimulationMode {
            lastSyncTime = Date()
            return
        }
        guard let p = connectedPeripheral, let char = timeCharacteristic else { return }
        p.writeValue(packet, for: char, type: .withoutResponse)
        lastSyncTime = Date()
    }

    public func updateWatchSettings(_ settings: WatchSettings) {
        let packet = ForeverBandProtocol.buildWatchSettingsPacket(settings: settings)
        if isSimulationMode { return }
        guard let p = connectedPeripheral, let char = watchSettingsCharacteristic else { return }
        p.writeValue(packet, for: char, type: .withoutResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension ForeverBandBLEManager: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn && !self.isSimulationMode {
                self.startScanning()
            } else if central.state != .poweredOn {
                self.status = .disconnected
            }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.uppercased() } ?? []
            let targetUUIDString = ForeverBandProtocol.serviceUUID.uppercased()
            let isTarget = name.localizedCaseInsensitiveContains("ForeverBand")
                || name.localizedCaseInsensitiveContains("ForeverFit")
                || name.localizedCaseInsensitiveContains("ESP32")
                || serviceUUIDs.contains(targetUUIDString)

            // Strictly filter out non-ForeverBand peripherals
            guard isTarget else { return }

            if !self.discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredPeripherals.append(peripheral)
            }

            self.rssi = RSSI.intValue
            // If not yet connected and not in simulation, auto-connect to the ForeverBand
            if self.connectedPeripheral == nil && !self.isSimulationMode {
                self.connect(to: peripheral)
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = nil
            self.connectingPeripheralId = nil
            self.status = .connected
            self.connectedAt = Date()
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: ForeverBandProtocol.serviceUUID)])

            // Start 5-minute periodic clock sync so millis()-based firmware doesn't drift
            self.timeSyncTimer?.invalidate()
            self.timeSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncTimeToWatch()
                }
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = nil
            self.connectingPeripheralId = nil
            self.connectedPeripheral = nil
            self.status = .disconnected
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = nil
            self.connectingPeripheralId = nil
            self.status = .disconnected
            self.connectedPeripheral = nil
            self.connectedAt = nil
            self.timeSyncTimer?.invalidate()
            self.timeSyncTimer = nil
            self.vitalsCharacteristic = nil
            self.envCharacteristic = nil
            self.motionCharacteristic = nil
            self.timeCharacteristic = nil
            self.watchSettingsCharacteristic = nil

            if !self.isSimulationMode {
                self.startScanning()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension ForeverBandBLEManager: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == CBUUID(string: ForeverBandProtocol.serviceUUID) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        Task { @MainActor in
            for char in characteristics {
                let uuid = char.uuid.uuidString.uppercased()
                if uuid == ForeverBandProtocol.vitalsCharUUID {
                    self.vitalsCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                } else if uuid == ForeverBandProtocol.envCharUUID {
                    self.envCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                } else if uuid == ForeverBandProtocol.motionCharUUID {
                    self.motionCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                } else if uuid == ForeverBandProtocol.timeCharUUID {
                    self.timeCharacteristic = char
                    self.syncTimeToWatch()
                } else if uuid == ForeverBandProtocol.watchSettingsCharUUID {
                    self.watchSettingsCharacteristic = char
                    if let s = self.pendingWatchSettings {
                        self.updateWatchSettings(s)
                    }
                }
            }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()

        Task { @MainActor in
            if uuid == ForeverBandProtocol.vitalsCharUUID {
                if let v = ForeverBandProtocol.parseVitals(data: data) {
                    self.latestVitals = v
                    self.onVitalsReceived?(v)
                }
            } else if uuid == ForeverBandProtocol.envCharUUID {
                if let e = ForeverBandProtocol.parseEnv(data: data) {
                    self.latestEnv = e
                    self.onEnvReceived?(e)
                }
            } else if uuid == ForeverBandProtocol.motionCharUUID {
                if let m = ForeverBandProtocol.parseMotion(data: data) {
                    self.latestMotion = m
                }
            }
        }
    }
}
