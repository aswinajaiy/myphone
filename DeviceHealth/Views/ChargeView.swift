import SwiftUI
import UIKit

/// Tab 2: live charge monitoring.
struct ChargeView: View {
    @EnvironmentObject var monitor: ChargeMonitor

    var body: some View {
        let s = monitor.snapshot
        NavigationStack {
            List {
                ChargeHeroSection(s: s)
                AccessBanner(snapshot: s)
                ChargeChartSection(samples: monitor.samples)
                PowerFlowSection(s: s)
                AdapterSection(s: s)
                if !s.adapter.pdProfiles.isEmpty {
                    PDProfilesSection(adapter: s.adapter)
                }
                ChargeControllerSection(s: s)
                SessionSection(monitor: monitor)
                MonitorSettingsSection(monitor: monitor)
            }
            .navigationTitle("Charging")
        }
    }
}

// MARK: - Hero

private struct ChargeHeroSection: View {
    let s: BatterySnapshot

    var body: some View {
        // Prefer the PMU's measured input; fall back to what's going into the cell.
        let measuredInput = s.inputWatts != nil
        let watts = s.inputWatts ?? s.batteryWatts
        let amps = s.inputAmps ?? s.batteryAmps
        let volts = s.inputVolts ?? s.batteryVolts

        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(s.connection.title, systemImage: s.connection.symbol)
                        .font(.headline)
                        .foregroundStyle(s.connection.isConnected ? Color.green : Color.secondary)
                    Spacer()
                    Text(Fmt.int(s.percent, "%"))
                        .font(.headline.monospacedDigit())
                }
                Text(s.chargeStateText).font(.subheadline).foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.num(watts, 2))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("W").font(.title2).foregroundStyle(.secondary)
                }
                Text(measuredInput ? "Measured input from charger" : "Battery power (input telemetry unavailable)")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    StatTile(title: "Current", value: Fmt.num(amps, 3), unit: "A", tint: .orange)
                    StatTile(title: "Voltage", value: Fmt.num(volts, 2), unit: "V", tint: .blue)
                }
                HStack(spacing: 10) {
                    StatTile(title: "Into battery", value: Fmt.num(s.batteryWatts, 2), unit: "W", tint: .green)
                    StatTile(title: "Charger rating", value: Fmt.int(s.adapter.watts), unit: "W", tint: .purple)
                }
            }
            .padding(.vertical, 6)
            .animation(.default, value: watts)
        }
    }
}

// MARK: - Chart

private struct ChargeChartSection: View {
    let samples: [ChargeSample]
    @State private var metric: ChartMetric = .watts
    @State private var window: TimeInterval = 300

    var body: some View {
        Section("Live") {
            Picker("Metric", selection: $metric) {
                ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ChargeChart(samples: samples, metric: metric, window: window)
            Picker("Window", selection: $window) {
                Text("1 min").tag(TimeInterval(60))
                Text("5 min").tag(TimeInterval(300))
                Text("15 min").tag(TimeInterval(900))
                Text("1 hr").tag(TimeInterval(3600))
                Text("All").tag(TimeInterval.greatestFiniteMagnitude)
            }
        }
    }
}

// MARK: - Details

private struct PowerFlowSection: View {
    let s: BatterySnapshot

    var body: some View {
        let efficiency: Double? = {
            guard let i = s.inputWatts, i > 0.1, let b = s.batteryWatts, b > 0 else { return nil }
            return b / i * 100
        }()
        Section {
            MetricRow("From charger", Fmt.num(s.inputWatts, 2, "W"), symbol: "powerplug", tint: .yellow)
            MetricRow("Input current", Fmt.num(s.inputAmps, 3, "A"))
            MetricRow("Input voltage", Fmt.num(s.inputVolts, 3, "V"))
            MetricRow("Into battery", Fmt.num(s.batteryWatts, 2, "W"), symbol: "battery.100.bolt", tint: .green)
            MetricRow("Battery current", Fmt.num(s.batteryAmps, 3, "A"), detail: "Negative = discharging")
            MetricRow("Instant battery current", Fmt.milli(s.instantAmperage_mA, "A"))
            MetricRow("Battery voltage", Fmt.num(s.batteryVolts, 3, "V"))
            MetricRow("Phone is using", Fmt.num(s.systemLoadWatts, 2, "W"), symbol: "iphone", tint: .blue)
            MetricRow("Conversion loss", Fmt.milli(s.telemetry.adapterEfficiencyLoss_mW, "W", digits: 2))
            MetricRow("Battery share of input", Fmt.percent(efficiency, digits: 0))
            MetricRow("Battery temperature", Fmt.temp(s.temperatureC))
        } header: {
            Text("Power flow")
        } footer: {
            Text("\"From charger\" is the PMU's measured input (PowerTelemetryData). \"Into battery\" is cell voltage × cell current.")
        }
    }
}

private struct AdapterSection: View {
    let s: BatterySnapshot

    var body: some View {
        let a = s.adapter
        let negotiated: Double? = {
            guard let v = a.voltage_mV, let i = a.current_mA else { return nil }
            return Double(v) * Double(i) / 1_000_000
        }()
        Section("Charger / adapter") {
            MetricRow("Connection", s.connection.title, symbol: s.connection.symbol)
            MetricRow("Rated power", Fmt.int(a.watts, "W"))
            MetricRow("Negotiated voltage", Fmt.milli(a.voltage_mV, "V", digits: 2))
            MetricRow("Negotiated current limit", Fmt.milli(a.current_mA, "A", digits: 2))
            MetricRow("Negotiated power", Fmt.num(negotiated, 1, "W"))
            MetricRow("Wireless", Fmt.bool(a.isWireless))
            MetricRow("Name", Fmt.str(a.name))
            MetricRow("Manufacturer", Fmt.str(a.manufacturer))
            MetricRow("Model", Fmt.str(a.model))
            MetricRow("Serial", Fmt.str(a.serial))
            MetricRow("Firmware", Fmt.str(a.firmwareVersion))
            MetricRow("Hardware", Fmt.str(a.hardwareVersion))
            MetricRow("Description", Fmt.str(a.description))
            MetricRow("Family code", Fmt.hex(a.familyCode))
            if !a.raw.isEmpty {
                NavigationLink("All adapter fields") { RawDictView(title: "AdapterDetails", dict: a.raw) }
            }
        }
    }
}

private struct PDProfilesSection: View {
    let adapter: AdapterInfo

    var body: some View {
        Section {
            ForEach(adapter.pdProfiles) { p in
                let active = p.index == adapter.activeProfileIndex
                HStack {
                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(active ? Color.green : Color.secondary)
                    Text(String(format: "%.1f V", Double(p.maxVoltage_mV) / 1000))
                    Text("@ " + String(format: "%.2f A", Double(p.maxCurrent_mA) / 1000))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f W", p.watts)).monospacedDigit()
                }
            }
        } header: {
            Text("USB-PD source profiles")
        } footer: {
            Text("Power profiles the charger advertised. The checked one is in use.")
        }
    }
}

private struct ChargeControllerSection: View {
    let s: BatterySnapshot

    var body: some View {
        let c = s.charger
        Section("Charge controller") {
            MetricRow("State", s.chargeStateText)
            MetricRow("Target charge current", Fmt.milli(c.chargingCurrent_mA, "A"))
            MetricRow("Target charge voltage", Fmt.milli(c.chargingVoltage_mV, "V"))
            MetricRow("Not-charging reason", Fmt.hex(c.notChargingReason), detail: "0 = none")
            MetricRow("Slow-charging reason", Fmt.hex(c.slowChargingReason))
            MetricRow("Input voltage limit", Fmt.milli(c.vacVoltageLimit_mV, "V"))
            MetricRow("Time thermally limited", Fmt.int(c.timeChargingThermallyLimited, "s"))
            MetricRow("Charger ID", Fmt.hex(c.chargerID))
            MetricRow("Time to full", Fmt.minutes(s.timeToFull_min))
            MetricRow("Charge capable", Fmt.bool(s.externalChargeCapable))
            if !c.raw.isEmpty {
                NavigationLink("All charger fields") { RawDictView(title: "ChargerData", dict: c.raw) }
            }
            if !s.telemetry.raw.isEmpty {
                NavigationLink("All power telemetry") { RawDictView(title: "PowerTelemetryData", dict: s.telemetry.raw) }
            }
        }
    }
}

// MARK: - Session

private struct SessionSection: View {
    @ObservedObject var monitor: ChargeMonitor
    @State private var exportURL: ExportItem?

    var body: some View {
        Section {
            if let ses = monitor.session {
                MetricRow("Status", ses.isActive ? "Active" : "Ended", tint: ses.isActive ? .green : nil)
                MetricRow("Connection", ses.connection.title)
                MetricRow("Started", ses.start.formatted(date: .omitted, time: .shortened))
                MetricRow("Duration", Fmt.duration(ses.duration))
                MetricRow("Charge", "\(Fmt.int(ses.startPercent, "%")) → \(Fmt.int(ses.currentPercent, "%"))",
                          detail: ses.percentGained.map { "+\($0)%" })
                MetricRow("Energy from charger", Fmt.num(ses.energyIn_Wh, 2, "Wh"))
                MetricRow("Energy into battery", Fmt.num(ses.energyIntoBattery_Wh, 2, "Wh"))
                MetricRow("Charge into battery", Fmt.num(ses.chargeIntoBattery_mAh, 0, "mAh"))
                MetricRow("Peak input", Fmt.num(ses.peakInputW, 2, "W"))
                MetricRow("Average input", Fmt.num(ses.averageInputW, 2, "W"))
                MetricRow("Peak battery current", Fmt.num(ses.peakBatteryA, 3, "A"))
                MetricRow("Max battery temp", Fmt.temp(ses.maxTempC))
            } else {
                Text("Plug in to start a session.").foregroundStyle(.secondary)
            }
            Button {
                if let url = monitor.exportCSV() { exportURL = ExportItem(url: url) }
            } label: {
                Label("Export samples as CSV (\(monitor.samples.count))", systemImage: "square.and.arrow.up")
            }
            .disabled(monitor.samples.isEmpty)
            Button("Reset session & chart", role: .destructive) { monitor.resetSession() }
        } header: {
            Text("Session")
        }
        .sheet(item: $exportURL) { item in
            ActivityView(items: [item.url])
        }
    }
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct MonitorSettingsSection: View {
    @ObservedObject var monitor: ChargeMonitor

    var body: some View {
        Section("Monitor") {
            Picker("Sample every", selection: $monitor.interval) {
                Text("0.5 s").tag(0.5)
                Text("1 s").tag(1.0)
                Text("2 s").tag(2.0)
                Text("5 s").tag(5.0)
            }
            Toggle("Keep screen awake", isOn: $monitor.keepAwake)
        }
    }
}
