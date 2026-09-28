import SwiftUI

public struct MetricCardView<Accessory: View>: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let value: String
    public let unit: String
    public let statusText: String
    public let statusColor: Color
    public let onTap: (() -> Void)?
    public let accessory: Accessory?

    public init(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        unit: String,
        statusText: String,
        statusColor: Color,
        onTap: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.unit = unit
        self.statusText = statusText
        self.statusColor = statusColor
        self.onTap = onTap
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(statusColor.opacity(0.12))
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)

                Spacer()

                if let acc = accessory {
                    acc
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(0.4),
                                    Color.white.opacity(0.04),
                                    iconColor.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

public extension MetricCardView where Accessory == EmptyView {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        unit: String,
        statusText: String? = nil,
        statusColor: Color? = nil,
        warn: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        let sText = statusText ?? (warn ? "Warning" : (value == "--" ? "Offline" : "Normal"))
        let sColor = statusColor ?? (warn ? LiquidGlassTheme.alertCrimson : (value == "--" ? Color.white.opacity(0.4) : LiquidGlassTheme.statusNormal))
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            value: value,
            unit: unit,
            statusText: sText,
            statusColor: sColor,
            onTap: onTap,
            accessory: { EmptyView() }
        )
    }
}
