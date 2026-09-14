import SwiftUI
import Charts

public enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case all = "All"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3 Months"
        case .all: return "All Time"
        }
    }
}

public struct MetricHistoryItem: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double
    public let displayString: String

    public init(id: UUID = UUID(), timestamp: Date, value: Double, displayString: String) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.displayString = displayString
    }
}

public struct MetricHistoryView: View {
    public let title: String
    public let unit: String
    public let accentColor: Color
    public let items: [MetricHistoryItem]
    public let onAddEntry: (() -> Void)?
    public let onDeleteEntry: ((UUID) -> Void)?

    @State private var selectedPeriod: HistoryPeriod = .week

    public init(
        title: String,
        unit: String,
        accentColor: Color = LiquidGlassTheme.neonCyan,
        items: [MetricHistoryItem],
        onAddEntry: (() -> Void)? = nil,
        onDeleteEntry: ((UUID) -> Void)? = nil
    ) {
        self.title = title
        self.unit = unit
        self.accentColor = accentColor
        self.items = items
        self.onAddEntry = onAddEntry
        self.onDeleteEntry = onDeleteEntry
    }

    private var filteredItems: [MetricHistoryItem] {
        let now = Date()
        let cutoff: Date
        switch selectedPeriod {
        case .week: cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        case .threeMonths: cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        case .all: cutoff = Date.distantPast
        }
        return items.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    private var averageValue: Double? {
        guard !filteredItems.isEmpty else { return nil }
        let sum = filteredItems.reduce(0.0) { $0 + $1.value }
        return sum / Double(filteredItems.count)
    }

    private var minValue: Double? {
        filteredItems.map(\.value).min()
    }

    private var maxValue: Double? {
        filteredItems.map(\.value).max()
    }

    private var netChange: Double? {
        guard filteredItems.count >= 2, let first = filteredItems.first?.value, let last = filteredItems.last?.value else { return nil }
        return last - first
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Period Selector
                HStack(spacing: 8) {
                    ForEach(HistoryPeriod.allCases) { p in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPeriod = p
                            }
                        } label: {
                            Text(p.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(selectedPeriod == p ? Color.black : Color.white.opacity(0.8))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedPeriod == p ? accentColor : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 8)

                // Stats Cards Row
                HStack(spacing: 10) {
                    statCard(title: "Average", value: averageValue != nil ? String(format: "%.1f", averageValue!) : "--", unit: unit)
                    statCard(title: "Range", value: (minValue != nil && maxValue != nil) ? "\(Int(minValue!))–\(Int(maxValue!))" : "--", unit: unit)
                    statCard(title: "Change", value: netChange != nil ? String(format: "%+.1f", netChange!) : "--", unit: unit)
                }

                // Interactive Chart
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(title) Trend")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    if filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Text("No recorded data for this period.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                    } else {
                        Chart {
                            ForEach(filteredItems) { item in
                                LineMark(
                                    x: .value("Time", item.timestamp),
                                    y: .value("Value", item.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                                AreaMark(
                                    x: .value("Time", item.timestamp),
                                    y: .value("Value", item.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.35), accentColor.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                PointMark(
                                    x: .value("Time", item.timestamp),
                                    y: .value("Value", item.value)
                                )
                                .foregroundStyle(Color.white)
                            }
                        }
                        .frame(height: 200)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                    }
                }

                // Add Entry Action (if applicable)
                if let onAdd = onAddEntry {
                    Button {
                        onAdd()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Log \(title)")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                // Recent Entries
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Entries")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    VStack(spacing: 8) {
                        ForEach(items.sorted { $0.timestamp > $1.timestamp }) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayString)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }
                                Spacer()

                                if let onDelete = onDeleteEntry {
                                    Button {
                                        onDelete(item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                    }
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }

    private func statCard(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }
}
