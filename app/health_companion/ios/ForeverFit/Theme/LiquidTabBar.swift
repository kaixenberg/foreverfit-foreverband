import SwiftUI

public enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case aiAssistant = "AI Health"
    case disaster = "Disaster"
    case healthLog = "Health Log"
    case wearable = "Wearable"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "waveform.path.ecg"
        case .aiAssistant: return "sparkles"
        case .disaster: return "shield.lefthalf.filled"
        case .healthLog: return "heart.text.square.fill"
        case .wearable: return "applewatch.side.right"
        }
    }

    public var activeColor: Color {
        switch self {
        case .dashboard: return LiquidGlassTheme.emeraldGreen
        case .aiAssistant: return LiquidGlassTheme.violetGlow
        case .disaster: return LiquidGlassTheme.amberWarning
        case .healthLog: return LiquidGlassTheme.neonCyan
        case .wearable: return Color.white
        }
    }
}

/// Floating Liquid-Glass Tab Bar with fluid selection indicator and haptics
public struct LiquidTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabNamespace

    public init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        selectedTab = tab
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: isSelected ? 18 : 16, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? tab.activeColor : Color.white.opacity(0.55))
                            .frame(height: 22)

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(tab.activeColor.opacity(0.18))
                                .matchedGeometryEffect(id: "liquidTabSelection", in: tabNamespace)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(tab.activeColor.opacity(0.5), lineWidth: 1.0)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }
}
