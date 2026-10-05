import SwiftUI

/// Tab 1: high-level dashboard. Each card links to the tab or page with the details.
struct OverviewView: View {
    @EnvironmentObject var model: HealthModel
    @EnvironmentObject var monitor: ChargeMonitor
    @Binding var tab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        BatteryDetailView()
                    } label: {
                        BatteryCard(b: model.battery, estimate: monitor.estimate)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 16) {
                        Button { tab = .system } label: { CPUCard(model: model) }
                            .buttonStyle(.plain)
                        Button { tab = .system } label: { MemoryCard(m: model.memory) }
                            .buttonStyle(.plain)
                    }

                    Button { tab = .network } label: { NetworkCard(model: model) }
                        .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
            .refreshable { model.refresh() }
        }
    }
}

// MARK: - Card chrome

private struct OverviewCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title, symbol: symbol, tint: tint)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Small caption-over-value pair used inside cards.
private struct MiniStat: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Battery

private struct BatteryCard: View {
    let b: BatterySnapshot
    let estimate: ChargeRateEstimate?

    /// Only show the charging strip while power is actually flowing into the cell.
    private var isCharging: Bool {
        b.externalConnected == true && b.isCharging == true && b.fullyCharged != true
    }

    var body: some View {
        let fraction = Double(b.percent ?? 0) / 100
        OverviewCard(title: "Battery", symbol: "battery.100", tint: .green) {
            HStack(spacing: 20) {
                RingGauge(fraction: fraction, tint: levelColor, lineWidth: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(Fmt.int(b.percent))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("%").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)

                // Only show stats this install can read, so Limited mode doesn't fill up with dashes.
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    if b.healthPercent != nil {
                        MiniStat(title: "Health", value: Fmt.percent(b.healthPercent, digits: 1), tint: healthColor)
                    }
                    if b.cycleCount != nil {
                        MiniStat(title: "Cycles", value: Fmt.int(b.cycleCount))
                    }
                    if b.temperatureC != nil {
                        MiniStat(title: "Temperature", value: Fmt.temp(b.temperatureC))
                    }
                    MiniStat(title: "State", value: b.externalConnected == true ? "Plugged in" : "On battery")
                    if !b.hasLiveTelemetry, let e = estimate {
                        MiniStat(title: "Charge rate", value: Fmt.num(e.percentPerHour, 0, "%/h"))
                    }
                }
                Spacer(minLength: 0)
            }

            if isCharging {
                ChargingStrip(b: b, estimate: estimate)
            }
        }
    }

    private var levelColor: Color {
        guard let p = b.percent else { return .secondary }
        return isCharging ? .green : p <= 20 ? .red : p <= 40 ? .orange : .green
    }

    private var healthColor: Color {
        guard let h = b.healthPercent else { return .secondary }
        return h >= 90 ? .green : h >= 80 ? .yellow : .red
    }
}

/// Charge %, live watts and estimated completion time, shown only while charging.
private struct ChargingStrip: View {
    let b: BatterySnapshot
    let estimate: ChargeRateEstimate?

    var body: some View {
        // Prefer the PMU's measured input, then what's going into the cell, then the % estimate.
        let measured = b.inputWatts ?? b.batteryWatts
        let watts = measured ?? estimate?.watts
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Charging · \(Fmt.int(b.percent, "%"))")
                    .font(.subheadline.weight(.semibold))
                Text(completionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text((measured == nil && watts != nil ? "≈" : "") + Fmt.num(watts, 1))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("W").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var completionText: String {
        guard let m = b.timeToFullEstimate(estimate) else { return "Estimating time to full…" }
        let eta = Date().addingTimeInterval(TimeInterval(m * 60))
        let approx = b.reportedTimeToFull_min == nil ? "~" : ""
        return "Full by \(approx)\(eta.formatted(date: .omitted, time: .shortened)) · \(Fmt.minutes(m)) left"
    }
}

// MARK: - CPU & memory

private struct CPUCard: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        let total = (model.cpuUser ?? 0) + (model.cpuSystem ?? 0)
        OverviewCard(title: "CPU", symbol: "cpu", tint: .blue) {
            UsageRing(fraction: total)
            Text("\(ProcessInfo.processInfo.activeProcessorCount) cores active")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MemoryCard: View {
    let m: MemoryStats

    var body: some View {
        let fraction = m.total > 0 ? Double(m.used) / Double(m.total) : 0
        OverviewCard(title: "Memory", symbol: "memorychip", tint: .purple) {
            UsageRing(fraction: fraction)
            Text("\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct UsageRing: View {
    let fraction: Double

    var body: some View {
        RingGauge(fraction: fraction, tint: UsageBar.loadColor(fraction), lineWidth: 10) {
            Text(Fmt.percent(fraction * 100))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 92, height: 92)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Network

private struct NetworkCard: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        OverviewCard(title: "Network", symbol: "antenna.radiowaves.left.and.right", tint: .teal) {
            HStack(alignment: .top, spacing: 16) {
                InterfaceRates(title: "Wi-Fi", symbol: "wifi", tint: .blue, rate: model.wifiRate)
                Divider()
                InterfaceRates(title: "Cellular", symbol: "cellularbars", tint: .green, rate: model.cellRate)
            }
        }
    }
}

private struct InterfaceRates: View {
    let title: String
    let symbol: String
    let tint: Color
    let rate: (rx: Double, tx: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            rateRow("arrow.down", rate.rx)
            rateRow("arrow.up", rate.tx)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateRow(_ symbol: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(Fmt.rate(value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    OverviewView(tab: .constant(.overview))
        .environmentObject(HealthModel())
        .environmentObject(ChargeMonitor())
}
