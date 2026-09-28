import SwiftUI
import CoreBluetooth

public struct ScanConnectView: View {
    @ObservedObject var bleManager: ForeverBandBLEManager
    @Environment(\.dismiss) private var dismiss

    public init(bleManager: ForeverBandBLEManager) {
        self.bleManager = bleManager
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header Status Card
                VStack(spacing: 8) {
                    Image(systemName: bleManager.status == .connected ? "checkmark.circle.fill" : "wave.3.forward.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(bleManager.status == .connected ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.neonCyan)

                    Text(bleManager.status == .connected ? "ForeverBand Connected" : (bleManager.status == .scanning ? "Scanning for Wearable…" : "Connect ForeverBand"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text("Make sure your ESP32 ForeverBand is powered on and within Bluetooth range.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 20)

                // Discovered Devices List
                if bleManager.discoveredPeripherals.isEmpty && bleManager.status == .scanning {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(LiquidGlassTheme.neonCyan)
                            .scaleEffect(1.2)
                        Text("Looking for ForeverBand peripherals…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Spacer()
                } else if bleManager.discoveredPeripherals.isEmpty && bleManager.status != .scanning && bleManager.status != .connected {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text("No devices found yet.\nTap 'Scan Again' below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                            HStack(spacing: 14) {
                                Image(systemName: "applewatch")
                                    .font(.system(size: 24))
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: peripheral))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text(peripheral.identifier.uuidString)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.5))
                                }

                                Spacer()

                                if bleManager.status == .connecting && bleManager.connectingPeripheralId == peripheral.identifier {
                                    ProgressView()
                                        .tint(LiquidGlassTheme.neonCyan)
                                } else if bleManager.status == .connected && bleManager.connectedPeripheral?.identifier == peripheral.identifier {
                                    Text("Connected")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                                } else {
                                    Button("Connect") {
                                        bleManager.connect(to: peripheral)
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(LiquidGlassTheme.neonCyan)
                                    .disabled(bleManager.status == .connecting)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // Bottom Action Bar
                HStack(spacing: 12) {
                    if bleManager.status == .connected {
                        Button("Disconnect Wearable") {
                            bleManager.disconnect()
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    } else {
                        Button {
                            bleManager.startScan()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(bleManager.status == .scanning ? "Scanning…" : "Scan Again")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LiquidGlassTheme.neonCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(bleManager.status == .scanning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Wearable Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Wearable Pairing")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .background(MeshGradientBackground())
        }
        .onAppear {
            if bleManager.status != .connected && bleManager.status != .scanning {
                bleManager.startScan()
            }
        }
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        if let name = peripheral.name, !name.isEmpty {
            return name
        }
        return "ForeverBand (\(peripheral.identifier.uuidString.prefix(4)))"
    }
}
