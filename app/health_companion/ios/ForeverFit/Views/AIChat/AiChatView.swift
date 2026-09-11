import SwiftUI
import PhotosUI

public struct AiChatView: View {
    @ObservedObject var chatService: AiChatService
    @ObservedObject var bleManager: ForeverBandBLEManager
    @ObservedObject var baselineService: BaselineService
    @ObservedObject var pedometerService: PedometerService
    @ObservedObject var disasterService: DisasterService
    @ObservedObject var dataStore: HealthDataStore

    @StateObject private var dictationService = VoiceDictationService()
    @State private var inputText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isScanningDocument = false
    @State private var showingSettingsSheet = false

    public init(
        chatService: AiChatService,
        bleManager: ForeverBandBLEManager,
        baselineService: BaselineService,
        pedometerService: PedometerService,
        disasterService: DisasterService,
        dataStore: HealthDataStore
    ) {
        self.chatService = chatService
        self.bleManager = bleManager
        self.baselineService = baselineService
        self.pedometerService = pedometerService
        self.disasterService = disasterService
        self.dataStore = dataStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            chatHeader

            // Model Download Prompt (if not installed)
            if !chatService.modelManager.status.isReady {
                modelDownloadBanner
            }

            // Grounded Health Telemetry Bar
            healthContextStatusBar

            // Message ScrollView
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(chatService.messages) { msg in
                            ChatBubbleView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                    .padding(.bottom, 10)
                }
                .onChange(of: chatService.messages.count) { _ in
                    if let last = chatService.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Quick Prompt Suggestions
            if chatService.messages.count <= 2 && !chatService.isGenerating {
                promptSuggestionsBar
            }

            // Bottom Input Bar
            inputBar
        }
        .sheet(isPresented: $showingSettingsSheet) {
            AiAssistantSettingsView()
        }
        .photosPicker(isPresented: $isScanningDocument, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    let extracted = await VisionReportAnalyzer.extractText(from: image)
                    if !extracted.isEmpty {
                        self.inputText = "Please analyze this medical report text:\n\(extracted)"
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.violetGlow)
                    Text("AI HEALTH COMPANION")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(LiquidGlassTheme.violetGlow)
                }
                Text("Gemma 4 E2B (On-Device)")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.white)
            }

            Spacer()

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            Button {
                chatService.clearConversation()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Model Download Banner

    private var modelDownloadBanner: some View {
        Button {
            showingSettingsSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LiquidGlassTheme.violetGlow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Download On-Device Model (~2.6 GB)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Gemma 4 E2B runs fully offline with zero internet required.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LiquidGlassTheme.violetGlow.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LiquidGlassTheme.violetGlow.opacity(0.4), lineWidth: 1))
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health Context Status Bar

    private var healthContextStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: bleManager.status == .connected ? "link.badge.checkmark" : "link.badge.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(bleManager.status == .connected ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.amberWarning)

            if bleManager.status == .connected && bleManager.latestVitals?.fingerPresent == true {
                let hr = "\(Int(bleManager.latestVitals!.heartRate)) bpm"
                let spo2 = "\(Int(bleManager.latestVitals!.spo2))%"
                Text("Grounded: \(hr) • \(spo2) • \(pedometerService.todaySteps) steps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else if bleManager.status == .connected {
                Text("Wearable Connected (No Finger Contact) • \(pedometerService.todaySteps) steps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            } else {
                Text("Wearable Disconnected • Grounded in Health Log & \(pedometerService.todaySteps) steps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Quick Suggestions Bar

    private var promptSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                suggestionPill("Is my heart rate normal?")
                suggestionPill("Explain my blood oxygen")
                suggestionPill("Review today's activity")
                suggestionPill("Check extreme heat risk")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func suggestionPill(_ text: String) -> some View {
        Button {
            triggerSend(prompt: text)
        } label: {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Prescription Scanner Button (Vision OCR)
            Button {
                isScanningDocument = true
            } label: {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 36, height: 36)
            }

            // Dictation Button (Speech Framework)
            Button {
                if dictationService.isRecording {
                    dictationService.stopDictation()
                } else {
                    dictationService.startDictation { transcribed in
                        self.inputText = transcribed
                    }
                }
            } label: {
                Image(systemName: dictationService.isRecording ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(dictationService.isRecording ? LiquidGlassTheme.alertCrimson : Color.white.opacity(0.7))
                    .frame(width: 36, height: 36)
            }

            // Text Field
            TextField("Ask health assistant...", text: $inputText)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                }
                .foregroundStyle(Color.white)
                .onSubmit {
                    triggerSend(prompt: inputText)
                }

            // Send Button
            Button {
                triggerSend(prompt: inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(inputText.isEmpty ? Color.white.opacity(0.3) : LiquidGlassTheme.neonCyan)
            }
            .disabled(inputText.isEmpty || chatService.isGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
        .padding(.horizontal)
        .padding(.bottom, 90)
    }

    private func triggerSend(prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let currentContext = HealthContextBuilder.build(
            userProfile: dataStore.userProfile,
            medicalId: dataStore.medicalId,
            vitals: bleManager.latestVitals,
            env: bleManager.latestEnv,
            baseline: baselineService,
            todaySteps: pedometerService.todaySteps,
            currentActivity: .still,
            latestBP: dataStore.bloodPressureEntries.first,
            latestGlucose: dataStore.bloodGlucoseEntries.first,
            weather: disasterService.weather,
            airQuality: disasterService.airQuality
        )

        chatService.sendMessage(text: prompt, healthContext: currentContext)
        inputText = ""
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}
