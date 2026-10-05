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
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
