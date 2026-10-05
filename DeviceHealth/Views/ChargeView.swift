import SwiftUI
import UIKit

/// Tab 2: live charge monitoring.
struct ChargeView: View {
    @EnvironmentObject var monitor: ChargeMonitor

    var body: some View {
        let s = monitor.snapshot
        NavigationStack {
            List {
                ChargeHeroSection(s: s, estimate: monitor.estimate)
                AccessBanner(snapshot: s)
                if !s.hasLiveTelemetry {
                    ChargeRateSection(s: s, estimate: monitor.estimate)
                }
                ChargeChartSection(samples: monitor.samples)
                // Sections below need registry data; hide them when it isn't readable.
                if s.hasLiveTelemetry {
                    PowerFlowSection(s: s)
                }
                if s.access == .full || !s.adapter.isEmpty {
                    AdapterSection(s: s)
                }
                if !s.adapter.pdProfiles.isEmpty {
                    PDProfilesSection(adapter: s.adapter)
                }
                if s.access == .full {
                    ChargeControllerSection(s: s)
                }
                SessionSection(monitor: monitor)
                MonitorSettingsSection(monitor: monitor)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Charging")
        }
    }
}

// MARK: - Hero

private struct ChargeHeroSection: View {
    let s: BatterySnapshot
    let estimate: ChargeRateEstimate?

    var body: some View {
        // Prefer the PMU's measured input, then what's going into the cell, then the % estimate.
        let measuredInput = s.inputWatts != nil
        let measured = s.inputWatts ?? s.batteryWatts
        let watts = measured ?? estimate?.watts
        let amps = s.inputAmps ?? s.batteryAmps
        let volts = s.inputVolts ?? s.batteryVolts
        let connected = s.connection.isConnected
        let ringColor: Color = {
            guard let p = s.percent else { return .secondary }
            return connected ? .green : p <= 20 ? .red : p <= 40 ? .orange : .green
        }()

        Section {
            VStack(spacing: 12) {
                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: s.connection.symbol)
                            Text(s.connection.title)
                        }
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(connected ? Color.green : Color.secondary)
                        .background((connected ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
                        .layoutPriority(1)
                        Spacer()
                        Text(s.chargeStateText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    RingGauge(fraction: Double(s.percent ?? 0) / 100, tint: ringColor, lineWidth: 16) {
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text((measured == nil && watts != nil ? "≈" : "") + Fmt.num(watts, measured == nil ? 1 : 2))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text("W").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: connected ? "bolt.fill" : "battery.100")
                                Text(Fmt.int(s.percent, "%"))
                            }
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ringColor)
                        }
                        .padding(.horizontal, 24)
                    }
                    .frame(width: 200, height: 200)

                    Text(powerCaption(measuredInput: measuredInput, measured: measured))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    if s.hasLiveTelemetry {
                        StatTile(title: "Current", value: Fmt.num(amps, 3), unit: "A",
                                 symbol: "bolt.horizontal", tint: .orange)
                        StatTile(title: "Voltage", value: Fmt.num(volts, 2), unit: "V",
                                 symbol: "waveform.path.ecg", tint: .blue)
                        StatTile(title: "Into battery", value: Fmt.num(s.batteryWatts, 2), unit: "W",
                                 symbol: "battery.100.bolt", tint: .green)
                    } else {
                        // Fallback tiles derived from the charge-% rate.
                        StatTile(title: "Charge rate", value: Fmt.num(estimate?.percentPerHour, 0), unit: "%/h",
                                 symbol: "speedometer", tint: .orange)
                        StatTile(title: "Time to full", value: Fmt.minutes(s.timeToFullEstimate(estimate)), unit: "",
                                 symbol: "hourglass", tint: .blue)
                        StatTile(title: "Est. current", value: Fmt.num(estimate?.mAhPerHour, 0), unit: "mA",
                                 symbol: "battery.100.bolt", tint: .green)
                    }
                    if s.hasLiveTelemetry || s.adapter.watts != nil {
                        StatTile(title: "Charger rating", value: Fmt.int(s.adapter.watts), unit: "W",
                                 symbol: "powerplug", tint: .purple)
                    } else {
                        StatTile(title: "Gained", value: estimate.map { "+\($0.percentGained)" } ?? Fmt.dash, unit: "%",
                                 symbol: "arrow.up.right", tint: .purple)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .animation(.default, value: watts)
        }
    }

    private func powerCaption(measuredInput: Bool, measured: Double?) -> String {
        if measuredInput { return "Measured input from charger" }
        if measured != nil { return "Battery power (input telemetry unavailable)" }
        guard s.isCharging == true, s.fullyCharged != true else { return "Not charging" }
        if estimate?.watts != nil { return "Estimated from how fast the charge % rises" }
        return "Measuring charge rate… needs a 2% rise"
    }
}

// MARK: - Charge rate fallback

/// Shown when the sandbox hides live current/voltage: everything here is derived from % ticks.
private struct ChargeRateSection: View {
    let s: BatterySnapshot
    let estimate: ChargeRateEstimate?

    var body: some View {
        Section {
            if let e = estimate {
                MetricRow("Charge rate", Fmt.num(e.percentPerHour, 1, "%/h"),
                          symbol: "speedometer", tint: .orange)
                MetricRow("Est. charge current", e.mAhPerHour.map { "≈ " + Fmt.num($0, 0, "mA") } ?? Fmt.dash,
                          detail: capacityDetail(e))
                MetricRow("Est. power into battery", e.watts.map { "≈ " + Fmt.num($0, 1, "W") } ?? Fmt.dash,
                          detail: "Assumes \(Fmt.num(ChargeRateEstimator.nominalVoltage, 2, "V")) nominal cell voltage")
                MetricRow("Time to full", Fmt.minutes(s.timeToFullEstimate(e)),
                          detail: s.reportedTimeToFull_min != nil ? "Reported by iOS" : "Estimated from charge rate")
                MetricRow("Measured over", Fmt.duration(e.window), detail: "\(e.percentGained)% gained in that time")
            } else if s.isCharging == true, s.fullyCharged != true {
                Label("Measuring… the rate appears after the charge rises 2%.", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else {
                Label("Plug in to measure charging speed.", systemImage: "powerplug")
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Charge rate (estimated)", symbol: "speedometer", tint: .orange)
        } footer: {
            Text("iOS hides live current and voltage from this app, so these figures come from how quickly the charge % rises over the last 30 minutes. They settle after a few percent and lag sudden changes. Optimized Charging may pause at 80%.")
        }
    }

    private func capacityDetail(_ e: ChargeRateEstimate) -> String {
        guard let c = e.capacity_mAh else { return "Battery capacity unknown for this model" }
        return "Based on \(c) mAh " + (e.capacityFromModelTable ? "(model spec)" : "(gas gauge)")
    }
}

// MARK: - Chart

private struct ChargeChartSection: View {
    let samples: [ChargeSample]
    @State private var metric: ChartMetric = .watts
    @State private var window: TimeInterval = 300

    var body: some View {
        // Only offer metrics this install can actually read.
        let available = ChartMetric.allCases.filter { m in samples.contains { $0.hasValue(for: m) } }
        let shown = available.contains(metric) ? metric : (available.first ?? .percent)
        Section {
            if available.count > 1 {
                Picker("Metric", selection: Binding(get: { shown }, set: { metric = $0 })) {
                    ForEach(available) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ChargeChart(samples: samples, metric: shown, window: window)
            Picker("Window", selection: $window) {
                Text("1 min").tag(TimeInterval(60))
                Text("5 min").tag(TimeInterval(300))
                Text("15 min").tag(TimeInterval(900))
                Text("1 hr").tag(TimeInterval(3600))
                Text("All").tag(TimeInterval.greatestFiniteMagnitude)
            }
        } header: {
            SectionHeader("Live", symbol: "chart.xyaxis.line", tint: .pink)
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
            SectionHeader("Power flow", symbol: "arrow.triangle.branch", tint: .yellow)
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
        Section {
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
        } header: {
            SectionHeader("Charger / adapter", symbol: "powerplug.fill", tint: .purple)
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
            SectionHeader("USB-PD source profiles", symbol: "cable.connector", tint: .blue)
        } footer: {
            Text("Power profiles the charger advertised. The checked one is in use.")
        }
    }
}

private struct ChargeControllerSection: View {
    let s: BatterySnapshot

    var body: some View {
        let c = s.charger
        Section {
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
        } header: {
            SectionHeader("Charge controller", symbol: "slider.horizontal.3", tint: .orange)
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
                MetricRow("Average rate", Fmt.num(averageRate(ses), 1, "%/h"))
                if monitor.snapshot.hasLiveTelemetry {
                    MetricRow("Energy from charger", Fmt.num(ses.energyIn_Wh, 2, "Wh"))
                    MetricRow("Energy into battery", Fmt.num(ses.energyIntoBattery_Wh, 2, "Wh"))
                    MetricRow("Charge into battery", Fmt.num(ses.chargeIntoBattery_mAh, 0, "mAh"))
                    MetricRow("Peak input", Fmt.num(ses.peakInputW, 2, "W"))
                    MetricRow("Average input", Fmt.num(ses.averageInputW, 2, "W"))
                    MetricRow("Peak battery current", Fmt.num(ses.peakBatteryA, 3, "A"))
                }
                if ses.maxTempC != nil {
                    MetricRow("Max battery temp", Fmt.temp(ses.maxTempC))
                }
            } else {
                Label("Plug in to start a session.", systemImage: "powerplug")
                    .foregroundStyle(.secondary)
            }
            Button {
                if let url = monitor.exportCSV() { exportURL = ExportItem(url: url) }
            } label: {
                Label("Export samples as CSV (\(monitor.samples.count))", systemImage: "square.and.arrow.up")
            }
            .disabled(monitor.samples.isEmpty)
            Button("Reset session & chart", role: .destructive) { monitor.resetSession() }
        } header: {
            SectionHeader("Session", symbol: "timer", tint: .green)
        }
        .sheet(item: $exportURL) { item in
            ActivityView(items: [item.url])
        }
    }

    private func averageRate(_ ses: ChargeSession) -> Double? {
        guard let gained = ses.percentGained, ses.duration >= 60 else { return nil }
        return Double(gained) / (ses.duration / 3600)
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
        Section {
            Picker("Sample every", selection: $monitor.interval) {
                Text("0.5 s").tag(0.5)
                Text("1 s").tag(1.0)
                Text("2 s").tag(2.0)
                Text("5 s").tag(5.0)
            }
            Toggle("Keep screen awake", isOn: $monitor.keepAwake)
        } header: {
            SectionHeader("Monitor", symbol: "gearshape.fill", tint: .gray)
        }
    }
}

#Preview {
    ChargeView().environmentObject(ChargeMonitor())
}
