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

/// Floating Liquid-Glass Tab Bar with fluid selection indicator, specular liquid highlight, and haptics
public struct LiquidTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabNamespace

    public init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        ZStack {
            // Layer 1: Sliding Liquid Pill Indicator (dedicated coordinate space for flawless spring animation)
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    ZStack {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tab.activeColor.opacity(0.30),
                                            tab.activeColor.opacity(0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay {
                                    // Specular liquid highlight rim
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: Color.white.opacity(0.85), location: 0.0),
                                                    .init(color: tab.activeColor.opacity(0.80), location: 0.25),
                                                    .init(color: tab.activeColor.opacity(0.30), location: 0.70),
                                                    .init(color: Color.white.opacity(0.20), location: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.2
                                        )
                                }
                                .overlay(alignment: .top) {
                                    // Liquid top reflection bead
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.70), Color.clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(height: 2)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 1.5)
                                }
                                .shadow(color: tab.activeColor.opacity(0.50), radius: 10, x: 0, y: 3)
                                .matchedGeometryEffect(id: "liquidSelectionPill", in: tabNamespace)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Layer 2: Interactive Tab Buttons
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = selectedTab == tab

                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) {
                            selectedTab = tab
                        }
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: isSelected ? 18 : 16, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? tab.activeColor : Color.white.opacity(0.55))
                                .frame(height: 22)
                                .scaleEffect(isSelected ? 1.14 : 1.0)
                                .shadow(color: isSelected ? tab.activeColor.opacity(0.7) : .clear, radius: 6, x: 0, y: 0)

                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.48))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.50), location: 0.0),
                                    .init(color: selectedTab.activeColor.opacity(0.40), location: 0.35),
                                    .init(color: Color.white.opacity(0.10), location: 0.70),
                                    .init(color: selectedTab.activeColor.opacity(0.25), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: Color.black.opacity(0.42), radius: 22, x: 0, y: 10)
                .shadow(color: selectedTab.activeColor.opacity(0.22), radius: 14, x: 0, y: 2)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.70), value: selectedTab)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
