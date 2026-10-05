import SwiftUI
import UIKit

/// A label/value row. Long-press copies the value.
struct MetricRow: View {
    let label: String
    let value: String
    var detail: String? = nil
    var symbol: String? = nil
    var tint: Color? = nil

    init(_ label: String, _ value: String, detail: String? = nil, symbol: String? = nil, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint ?? .secondary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy value", systemImage: "doc.on.doc")
            }
        }
    }
}

/// Large number tile used at the top of each tab.
struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    var symbol: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Section header with a small tinted SF Symbol badge.
struct SectionHeader: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor

    init(_ title: String, symbol: String, tint: Color = .accentColor) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
        }
    }
}

/// Circular progress ring with arbitrary center content.
struct RingGauge<Center: View>: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 12
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.6), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            center()
        }
        .animation(.easeInOut(duration: 0.6), value: fraction)
    }
}

/// Labelled horizontal usage bar with a colored capsule fill.
struct UsageBar: View {
    let title: String
    let value: String
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(geo.size.width * min(max(fraction, 0), 1), 6))
                }
            }
            .frame(height: 10)
            .animation(.easeInOut, value: fraction)
        }
        .padding(.vertical, 4)
    }

    /// Green → orange → red as usage rises.
    static func loadColor(_ fraction: Double) -> Color {
        fraction > 0.85 ? .red : fraction > 0.6 ? .orange : .green
    }
}

/// Shown when the deeper data sources were not readable on this install.
struct AccessBanner: View {
    let snapshot: BatterySnapshot

    var body: some View {
        if snapshot.access != .full {
            VStack(alignment: .leading, spacing: 6) {
                Label(snapshot.access.rawValue, systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("The private battery registry wasn't readable, so health, cycle count, live watts and charger details are limited. Install the TrollStore build (see README) for full data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = snapshot.registryError {
                    Text(err).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}
