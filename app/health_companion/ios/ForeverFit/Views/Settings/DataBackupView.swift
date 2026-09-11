import SwiftUI

public struct DataBackupView: View {
    @ObservedObject var dataStore: HealthDataStore

    @State private var showingExportSheet: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showingImportConfirm: Bool = false
    @State private var importJsonString: String = ""
    @State private var alertMessage: String? = nil

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Back up your complete health history, vitals telemetry, medications, and medical ID locally into a single JSON file. No cloud required.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                // Export Card
                VStack(alignment: .leading, spacing: 12) {
                    Label("Export Backup", systemImage: "square.and.arrow.up.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)

                    Text("Generate a JSON file containing your logged measurements, blood pressure, glucose, hydration, and medical contacts.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))

                    Button {
                        exportData()
                    } label: {
                        Text("Export All Data (JSON)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LiquidGlassTheme.neonCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))

                // Import Card
                VStack(alignment: .leading, spacing: 12) {
                    Label("Restore Backup", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.amberWarning)

                    Text("Restore previously exported health companion data. Warning: this will merge and update existing local records.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))

                    Button {
                        // For demonstration and file picking
                        alertMessage = "To restore from a backup file, share your .json backup to ForeverFit or copy-paste the JSON content."
                    } label: {
                        Text("Restore from File")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).stroke(LiquidGlassTheme.amberWarning, lineWidth: 1.5))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
            }
            .padding(16)
        }
        .navigationTitle("Data Export & Import")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert(item: Binding(get: {
            alertMessage != nil ? AlertItem(message: alertMessage!) : nil
        }, set: { _ in alertMessage = nil })) { item in
            Alert(title: Text("Backup Info"), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
    }

    private func exportData() {
        let json = dataStore.exportBackupJson()
        let filename = "health_companion_backup_\(Int(Date().timeIntervalSince1970)).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? json.write(to: tempURL, atomically: true, encoding: .utf8)
        self.exportURL = tempURL
        self.showingExportSheet = true
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
