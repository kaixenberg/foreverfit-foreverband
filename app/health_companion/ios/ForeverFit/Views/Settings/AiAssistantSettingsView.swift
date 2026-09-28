import SwiftUI

/// Settings view matching Android lib/screens/settings/ai_assistant_screen.dart
/// Manages Gemma 4 E2B download (~2.6 GB), removal, Wi-Fi restriction, and storage info.
public struct AiAssistantSettingsView: View {
    @ObservedObject var modelManager = GemmaModelManager.shared

    @State private var showingDownloadConfirm = false
    @State private var showingRemoveConfirm = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .aiAssistant)

                ScrollView {
                    VStack(spacing: 16) {
                        // Explanatory Card (matching Android card text)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "airplane")
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                                Text("100% AIRPLANE MODE COMPATIBLE")
                                    .font(.system(size: 11, weight: .black))
                                    .tracking(0.8)
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                            }
                            Text("This on-device chatbot runs entirely on your iPhone. Turn on airplane mode and it still answers, because it never talks to an external server.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineSpacing(3)
                        }
                        .padding()
                        .liquidGlass(highlightColor: LiquidGlassTheme.violetGlow.opacity(0.4))

                        // Model Status Card
                        modelStatusCard

                        // Wi-Fi Only Switch
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Wi-Fi only", isOn: $modelManager.wifiOnlyDownload)
                                .tint(LiquidGlassTheme.violetGlow)
                                .foregroundStyle(Color.white)
                            Text("Only download the model over Wi-Fi networks to prevent cellular data consumption.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .padding()
                        .liquidGlass()

                        // Storage Metrics
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Storage Footprint")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Text("Model file on local device disk")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                            Spacer()
                            Text(modelManager.modelDiskSizeString)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlassTheme.neonCyan)
                        }
                        .padding()
                        .liquidGlass()
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AI Assistant")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .alert("Download on-device AI assistant?", isPresented: $showingDownloadConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Download") {
                    do {
                        try modelManager.startDownload()
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            } message: {
                Text("This downloads Gemma 4 E2B, a ~2.6 GB AI model, to your phone so it can chat with you fully offline — no data ever leaves this device. The download can be large on mobile data; it defaults to Wi-Fi only. You can remove the model at any time to free up the space.")
            }
            .alert("Remove the AI assistant?", isPresented: $showingRemoveConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    modelManager.deleteModel()
                }
            } message: {
                Text("Deletes the downloaded model (~2.6 GB freed). You can download it again any time.")
            }
            .alert("Notice", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        switch modelManager.status {
        case .notInstalled:
            HStack {
                ZStack {
                    Circle()
                        .fill(LiquidGlassTheme.violetGlow.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LiquidGlassTheme.violetGlow)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable AI Assistant")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Downloads Gemma 4 E2B (~2.6 GB)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                Button {
                    showingDownloadConfirm = true
                } label: {
                    Text("Download")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white))
                }
            }
            .padding()
            .liquidGlass()

        case .downloading(let progress, let written, let total, let speed):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Downloading Gemma 4 E2B...")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }

                ProgressView(value: progress)
                    .tint(LiquidGlassTheme.neonCyan)

                HStack {
                    let mbWritten = Double(written) / (1024 * 1024)
                    let mbTotal = Double(total) / (1024 * 1024)
                    Text(String(format: "%.1f / %.1f MB (%.1f MB/s)", mbWritten, mbTotal, speed))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiquidGlassTheme.alertCrimson)
                }
            }
            .padding()
            .liquidGlass(highlightColor: LiquidGlassTheme.neonCyan.opacity(0.4))

        case .ready:
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Assistant is Ready")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Gemma 4 E2B running on-device")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Spacer()
                }

                Divider().background(Color.white.opacity(0.1))

                Button {
                    showingRemoveConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Model (Free ~2.6 GB)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiquidGlassTheme.alertCrimson)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .liquidGlass(highlightColor: LiquidGlassTheme.emeraldGreen.opacity(0.4))

        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                    Text("Download Failed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button("Retry Download") {
                    showingDownloadConfirm = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LiquidGlassTheme.neonCyan)
            }
            .padding()
            .liquidGlass(highlightColor: LiquidGlassTheme.alertCrimson.opacity(0.4))
        }
    }
}
