import SwiftUI

public struct ChatBubbleView: View {
    public let message: AiChatMessage

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(LiquidGlassTheme.violetGlow.opacity(0.2))
                        .frame(width: 30, height: 30)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.violetGlow)
                }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Grounded Context Badge (if user prompt had telemetry context)
                if let _ = message.attachedContext, message.role == .user {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.shield.half.filled")
                            .font(.system(size: 9))
                        Text("Live Vitals Attached")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(LiquidGlassTheme.neonCyan.opacity(0.8))
                    .padding(.bottom, 2)
                }

                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)

                if message.isStreaming {
                    HStack(spacing: 4) {
                        Circle().fill(LiquidGlassTheme.violetGlow).frame(width: 4, height: 4)
                        Circle().fill(LiquidGlassTheme.violetGlow).frame(width: 4, height: 4)
                        Circle().fill(LiquidGlassTheme.violetGlow).frame(width: 4, height: 4)
                    }
                    .padding(.top, 2)
                }

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [LiquidGlassTheme.neonCyan.opacity(0.4), LiquidGlassTheme.emeraldGreen.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.0)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(LiquidGlassTheme.violetGlow.opacity(0.3), lineWidth: 1.0)
                        }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}
