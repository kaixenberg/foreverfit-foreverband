import SwiftUI
import AVFoundation

public struct ImminentWarningView: View {
    public let hazards: [HazardType]
    public let reason: String?
    @Environment(\.dismiss) private var dismiss

    @State private var audioPlayer: AVAudioPlayer?

    public init(hazards: [HazardType], reason: String? = nil) {
        self.hazards = hazards
        self.reason = reason
    }

    public var body: some View {
        ZStack {
            // High visibility emergency background
            LiquidGlassTheme.alertCrimson
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60, weight: .black))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 10)

                    Text(hazards.count == 1 ? "\(hazards.first!.title) Warning" : "Multiple Hazard Warning")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)

                    if let r = reason {
                        Text(r)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 30)

                // Checklist actions
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(hazards) { hazard in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Image(systemName: hazard.iconName)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(LiquidGlassTheme.alertCrimson)

                                    Text(hazard.title)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Color.black)
                                }

                                Divider()

                                ForEach(hazard.actions, id: \.self) { act in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.black.opacity(0.7))
                                        Text(act)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.85))
                                    }
                                }
                            }
                            .padding(18)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Acknowledge Button
                Button {
                    stopAlarm()
                    dismiss()
                } label: {
                    Text("I Understand")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Color.black.opacity(0.3), radius: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            startAlarm()
        }
        .onDisappear {
            stopAlarm()
        }
    }

    private func startAlarm() {
        if let url = Bundle.main.url(forResource: "alarm_siren", withExtension: "wav") {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // infinite loop until dismissed
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        }
    }

    private func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
