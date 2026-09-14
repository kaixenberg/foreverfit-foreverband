import SwiftUI

/// Latched Emergency Alert Banner with 10s countdown, pulsing red liquid ring, and "I'm OK" button.
public struct EmergencyAlertBanner: View {
    @ObservedObject var fallDetector: FallDetectorService
    @State private var pulseScale: CGFloat = 1.0

    public init(fallDetector: FallDetectorService) {
        self.fallDetector = fallDetector
    }

    public var body: some View {
        if fallDetector.alertActive {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LiquidGlassTheme.alertCrimson.opacity(0.25))
                            .frame(width: 44, height: 44)
                            .scaleEffect(pulseScale)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(LiquidGlassTheme.alertCrimson)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fallDetector.alertSource == .manual ? "EMERGENCY SOS ACTIVE" : "POSSIBLE FALL DETECTED")
                            .font(.system(size: 13, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(LiquidGlassTheme.alertCrimson)

                        if let sec = fallDetector.secondsUntilCall {
                            Text("Calling emergency responders in \(sec)s...")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white)
                        } else if fallDetector.isCalling {
                            Text("Emergency protocol executing. Speaking alert...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(LiquidGlassTheme.amberWarning)
                        }
                    }

                    Spacer()

                    // Countdown Ring
                    if let sec = fallDetector.secondsUntilCall {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 3.5)
                            Circle()
                                .trim(from: 0, to: CGFloat(sec) / 10.0)
                                .stroke(LiquidGlassTheme.alertCrimson, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(sec)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 32, height: 32)
                    }
                }

                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        fallDetector.dismissAlert()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I'M OK — DISMISS")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(Color.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        fallDetector.onEmergencyTriggered?("user triggered immediate emergency dispatch")
                    } label: {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("CALL NOW")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(LiquidGlassTheme.alertCrimson)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(LiquidGlassTheme.alertCrimson.opacity(0.7), lineWidth: 1.5)
                    }
                    .shadow(color: LiquidGlassTheme.alertCrimson.opacity(0.4), radius: 20, x: 0, y: 8)
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            }
        }
    }
}
