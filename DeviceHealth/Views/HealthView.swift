import SwiftUI
import UIKit

/// Tab 1: overall device health. Each section is its own view so it's easy to delete
/// the ones you don't care about from `body`.
struct HealthView: View {
    @EnvironmentObject var model: HealthModel

    var body: some View {
        NavigationStack {
            List {
                HealthSummarySection(model: model)
                AccessBanner(snapshot: model.battery)
                BatteryHealthSection(b: model.battery)
                BatteryElectricalSection(b: model.battery)
                BatteryLifetimeSection(b: model.battery)
                ThermalSection(model: model)
                CPUSection(model: model)
                MemorySection(m: model.memory)
                StorageSection(s: model.storage)
                NetworkSection(model: model)
                DeviceSection(id: model.identity, uptime: model.uptime)
                DisplaySection()
                Section("Advanced") {
                    NavigationLink {
                        RawExplorerView(snapshot: model.battery)
                    } label: {
                        Label("Raw IORegistry explorer", systemImage: "list.bullet.indent")
                    }
                }
            }
            .navigationTitle("Device Health")
            .refreshable { model.refresh() }
        }
    }
}

// MARK: - Summary

private struct HealthSummarySection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        let b = model.battery
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Battery health", value: Fmt.num(b.healthPercent, 1), unit: "%",
                         tint: healthColor(b.healthPercent))
                StatTile(title: "Cycle count", value: Fmt.int(b.cycleCount), unit: "cycles")
                StatTile(title: "Battery temp", value: Fmt.num(b.temperatureC, 1), unit: "°C",
                         tint: tempColor(b.temperatureC))
                StatTile(title: "Thermal state", value: model.thermalState.label, unit: "",
                         tint: model.thermalState.color)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }

    private func healthColor(_ h: Double?) -> Color {
        guard let h else { return .secondary }
        return h >= 90 ? .green : h >= 80 ? .yellow : .red
    }

    private func tempColor(_ t: Double?) -> Color {
        guard let t else { return .secondary }
        return t < 35 ? .green : t < 40 ? .yellow : .red
    }
}

// MARK: - Battery

private struct BatteryHealthSection: View {
    let b: BatterySnapshot

    var body: some View {
        Section {
            MetricRow("Health (max capacity)", Fmt.percent(b.healthPercent, digits: 1),
                      detail: b.maximumCapacityPercent != nil ? "Reported by gas gauge" : "Full-charge ÷ design capacity")
            MetricRow("Design capacity", Fmt.int(b.designCapacity_mAh, "mAh"))
            MetricRow("Full-charge capacity", Fmt.int(b.nominalChargeCapacity_mAh, "mAh"), detail: "NominalChargeCapacity")
            MetricRow("Raw max capacity", Fmt.int(b.rawMaxCapacity_mAh, "mAh"), detail: "AppleRawMaxCapacity")
            MetricRow("Current charge", Fmt.int(b.rawCurrentCapacity_mAh, "mAh"))
            MetricRow("Charge level", Fmt.int(b.percent, "%"))
            MetricRow("Cycle count", Fmt.int(b.cycleCount))
            if !b.qmax_mAh.isEmpty {
                MetricRow("Qmax", b.qmax_mAh.map(String.init).joined(separator: " / ") + " mAh",
                          detail: "Chemical max capacity per cell")
            }
            MetricRow("Internal resistance", Fmt.int(b.weightedRa_mOhm, "mΩ"), detail: "WeightedRa — rises as the cell ages")
            MetricRow("Chemistry ID", Fmt.int(b.chemID))
            MetricRow("Manufacturer", Fmt.str(b.batteryManufacturer))
            MetricRow("Battery serial", Fmt.str(b.batterySerial))
            MetricRow("Gas gauge firmware", Fmt.str(b.gasGaugeFirmware))
            MetricRow("Data source", b.registryClass ?? b.access.rawValue)
        } header: {
            Text("Battery health")
        }
    }
}

private struct BatteryElectricalSection: View {
    let b: BatterySnapshot

    var body: some View {
        Section("Battery right now") {
            MetricRow("State", b.chargeStateText)
            MetricRow("Voltage", Fmt.milli(b.voltage_mV, "V"))
            if !b.cellVoltages_mV.isEmpty {
                MetricRow("Cell voltages", b.cellVoltages_mV.map { String(format: "%.3f", Double($0) / 1000) }.joined(separator: " / ") + " V")
            }
            MetricRow("Current", Fmt.milli(b.amperage_mA, "A"), detail: "Negative = discharging")
            MetricRow("Instant current", Fmt.milli(b.instantAmperage_mA, "A"))
            MetricRow("Power", Fmt.num(b.batteryWatts, 2, "W"))
            MetricRow("Temperature", Fmt.temp(b.temperatureC))
            MetricRow("Virtual temperature", Fmt.temp(b.virtualTemperatureC), detail: "Modelled skin/device temp")
            MetricRow("Time to empty", Fmt.minutes(b.timeToEmpty_min))
            MetricRow("Time to full", Fmt.minutes(b.timeToFull_min))
        }
    }
}

private struct BatteryLifetimeSection: View {
    let b: BatterySnapshot

    var body: some View {
        let l = b.lifetime
        if !l.isEmpty {
            Section("Battery lifetime") {
                MetricRow("Max temperature", Fmt.temp(normalizeLifetimeTemp(l.int("MaximumTemperature"))))
                MetricRow("Min temperature", Fmt.temp(normalizeLifetimeTemp(l.int("MinimumTemperature"))))
                MetricRow("Average temperature", Fmt.temp(normalizeLifetimeTemp(l.int("AverageTemperature"))))
                MetricRow("Max charge current", Fmt.milli(l.int("MaximumChargeCurrent"), "A"))
                MetricRow("Max discharge current", Fmt.milli(l.int("MaximumDischargeCurrent"), "A"))
                MetricRow("Max pack voltage", Fmt.milli(l.int("MaximumPackVoltage"), "V"))
                MetricRow("Min pack voltage", Fmt.milli(l.int("MinimumPackVoltage"), "V"))
                MetricRow("Total operating time", Fmt.int(l.int("TotalOperatingTime"), "h"))
                DisclosureGroup("All lifetime counters") {
                    ForEach(l.raw.keys.sorted(), id: \.self) { key in
                        MetricRow(key, RawFormat.scalar(l.raw[key] as Any))
                    }
                }
            }
        }
    }
}

// MARK: - System

private struct ThermalSection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        Section("Thermal & power") {
            MetricRow("Thermal state", model.thermalState.label, tint: model.thermalState.color)
            MetricRow("Battery temperature", Fmt.temp(model.battery.temperatureC))
            MetricRow("Low Power Mode", model.lowPowerMode ? "On" : "Off")
        }
    }
}

private struct CPUSection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        let total = (model.cpuUser ?? 0) + (model.cpuSystem ?? 0)
        Section("CPU") {
            MetricRow("Cores", "\(ProcessInfo.processInfo.activeProcessorCount) active / \(ProcessInfo.processInfo.processorCount)")
            MetricRow("Architecture", Fmt.str(model.identity.cpuArchitecture))
            VStack(alignment: .leading) {
                HStack {
                    Text("Usage (system-wide)")
                    Spacer()
                    Text(Fmt.percent(total * 100)).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(total, 0), 1))
                    .tint(total > 0.8 ? Color.red : total > 0.5 ? Color.orange : Color.green)
            }
            MetricRow("User", Fmt.percent(model.cpuUser.map { $0 * 100 }, digits: 1))
            MetricRow("System", Fmt.percent(model.cpuSystem.map { $0 * 100 }, digits: 1))
        }
    }
}

private struct MemorySection: View {
    let m: MemoryStats

    var body: some View {
        let fraction = m.total > 0 ? Double(m.used) / Double(m.total) : 0
        Section("Memory") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: min(fraction, 1))
            }
            MetricRow("Free", Fmt.bytes(m.free))
            MetricRow("Active", Fmt.bytes(m.active))
            MetricRow("Inactive", Fmt.bytes(m.inactive))
            MetricRow("Wired", Fmt.bytes(m.wired))
            MetricRow("Compressed", Fmt.bytes(m.compressed))
            MetricRow("Available to this app", Fmt.bytes(m.appAvailable))
        }
    }
}

private struct StorageSection: View {
    let s: StorageStats

    var body: some View {
        let used = s.total - s.availableImportant
        let fraction = s.total > 0 ? Double(used) / Double(s.total) : 0
        Section("Storage") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(Fmt.diskBytes(used)) of \(Fmt.diskBytes(s.total))").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(fraction, 0), 1))
            }
            MetricRow("Free (strict)", Fmt.diskBytes(s.available))
            MetricRow("Free (incl. purgeable)", Fmt.diskBytes(s.availableImportant))
            MetricRow("Free for optional data", Fmt.diskBytes(s.availableOpportunistic))
        }
    }
}

private struct NetworkSection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        let n = model.network
        Section {
            MetricRow("Wi-Fi ↓", Fmt.rate(model.wifiRate.rx), detail: "\(Fmt.diskBytes(n.wifiIn)) since boot")
            MetricRow("Wi-Fi ↑", Fmt.rate(model.wifiRate.tx), detail: "\(Fmt.diskBytes(n.wifiOut)) since boot")
            MetricRow("Cellular ↓", Fmt.rate(model.cellRate.rx), detail: "\(Fmt.diskBytes(n.cellIn)) since boot")
            MetricRow("Cellular ↑", Fmt.rate(model.cellRate.tx), detail: "\(Fmt.diskBytes(n.cellOut)) since boot")
        } header: {
            Text("Network")
        } footer: {
            Text("Since-boot totals come from 32-bit interface counters and wrap every 4 GB.")
        }
    }
}

private struct DeviceSection: View {
    let id: DeviceIdentity
    let uptime: TimeInterval

    var body: some View {
        Section {
            MetricRow("Model", Fmt.str(id.marketingName ?? id.machine))
            MetricRow("Identifier", id.machine)
            MetricRow("Model number", Fmt.str(id.modelNumber.map { $0 + (id.regionInfo ?? "") }))
            MetricRow("Color code", Fmt.str(id.deviceColor))
            MetricRow("Chip ID", Fmt.str(id.chipID))
            MetricRow("Serial number", Fmt.str(id.serialNumber))
            MetricRow("UDID", Fmt.str(id.udid))
            MetricRow("iOS", "\(id.osVersion) (\(id.osBuild))")
            MetricRow("Uptime", Fmt.duration(uptime))
            if let boot = id.bootTime {
                MetricRow("Last boot", boot.formatted(date: .abbreviated, time: .shortened))
            }
            DisclosureGroup("Kernel") {
                Text(id.kernelVersion).font(.caption.monospaced()).textSelection(.enabled)
            }
        } header: {
            Text("Device")
        } footer: {
            Text("Serial / UDID come from MobileGestalt protected keys and only appear in the TrollStore build.")
        }
    }
}

private struct DisplaySection: View {
    var body: some View {
        let screen = UIScreen.main
        Section("Display") {
            MetricRow("Brightness", Fmt.percent(Double(screen.brightness) * 100))
            MetricRow("Max refresh rate", "\(screen.maximumFramesPerSecond) Hz")
            MetricRow("Native resolution", "\(Int(screen.nativeBounds.width)) × \(Int(screen.nativeBounds.height))")
            MetricRow("Scale", Fmt.num(Double(screen.nativeScale), 2, "×"))
        }
    }
}
