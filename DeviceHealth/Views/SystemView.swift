import SwiftUI
import UIKit

/// Tab 2: detailed CPU, memory and storage metrics, plus device info.
struct SystemView: View {
    @EnvironmentObject var model: HealthModel

    var body: some View {
        NavigationStack {
            List {
                CPUSection(model: model)
                MemorySection(m: model.memory)
                StorageSection(s: model.storage)
                ThermalSection(model: model)
                DeviceSection(id: model.identity, uptime: model.uptime)
                DisplaySection()
                Section {
                    NavigationLink {
                        RawExplorerView(snapshot: model.battery)
                    } label: {
                        Label("Raw IORegistry explorer", systemImage: "list.bullet.indent")
                    }
                } header: {
                    SectionHeader("Advanced", symbol: "wrench.and.screwdriver.fill", tint: .gray)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("System")
            .refreshable { model.refresh() }
        }
    }
}

private struct CPUSection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        let total = (model.cpuUser ?? 0) + (model.cpuSystem ?? 0)
        Section {
            UsageBar(title: "Usage (system-wide)", value: Fmt.percent(total * 100),
                     fraction: total, tint: UsageBar.loadColor(total))
            MetricRow("User", Fmt.percent(model.cpuUser.map { $0 * 100 }, digits: 1))
            MetricRow("System", Fmt.percent(model.cpuSystem.map { $0 * 100 }, digits: 1))
            MetricRow("Cores", "\(ProcessInfo.processInfo.activeProcessorCount) active / \(ProcessInfo.processInfo.processorCount)")
            MetricRow("Architecture", Fmt.str(model.identity.cpuArchitecture))
        } header: {
            SectionHeader("CPU", symbol: "cpu", tint: .blue)
        }
    }
}

private struct MemorySection: View {
    let m: MemoryStats

    var body: some View {
        let fraction = m.total > 0 ? Double(m.used) / Double(m.total) : 0
        Section {
            UsageBar(title: "Used", value: "\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total))",
                     fraction: fraction, tint: UsageBar.loadColor(fraction))
            MetricRow("Free", Fmt.bytes(m.free))
            MetricRow("Active", Fmt.bytes(m.active))
            MetricRow("Inactive", Fmt.bytes(m.inactive))
            MetricRow("Wired", Fmt.bytes(m.wired))
            MetricRow("Compressed", Fmt.bytes(m.compressed))
            MetricRow("Available to this app", Fmt.bytes(m.appAvailable))
        } header: {
            SectionHeader("Memory", symbol: "memorychip", tint: .purple)
        }
    }
}

private struct StorageSection: View {
    let s: StorageStats

    var body: some View {
        let used = s.total - s.availableImportant
        let fraction = s.total > 0 ? Double(used) / Double(s.total) : 0
        Section {
            UsageBar(title: "Used", value: "\(Fmt.diskBytes(used)) of \(Fmt.diskBytes(s.total))",
                     fraction: fraction, tint: UsageBar.loadColor(fraction))
            MetricRow("Free (strict)", Fmt.diskBytes(s.available))
            MetricRow("Free (incl. purgeable)", Fmt.diskBytes(s.availableImportant))
            MetricRow("Free for optional data", Fmt.diskBytes(s.availableOpportunistic))
        } header: {
            SectionHeader("Storage", symbol: "internaldrive", tint: .gray)
        }
    }
}

private struct ThermalSection: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        Section {
            MetricRow("Thermal state", model.thermalState.label, tint: model.thermalState.color)
            MetricRow("Battery temperature", Fmt.temp(model.battery.temperatureC))
            MetricRow("Low Power Mode", model.lowPowerMode ? "On" : "Off",
                      tint: model.lowPowerMode ? .yellow : nil)
        } header: {
            SectionHeader("Thermal & power", symbol: "thermometer.medium", tint: .orange)
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
            SectionHeader("Device", symbol: "iphone", tint: .secondary)
        } footer: {
            Text("Serial / UDID come from MobileGestalt protected keys and only appear in the TrollStore build.")
        }
    }
}

private struct DisplaySection: View {
    var body: some View {
        let screen = UIScreen.main
        Section {
            MetricRow("Brightness", Fmt.percent(Double(screen.brightness) * 100))
            MetricRow("Max refresh rate", "\(screen.maximumFramesPerSecond) Hz")
            MetricRow("Native resolution", "\(Int(screen.nativeBounds.width)) × \(Int(screen.nativeBounds.height))")
            MetricRow("Scale", Fmt.num(Double(screen.nativeScale), 2, "×"))
        } header: {
            SectionHeader("Display", symbol: "sun.max.fill", tint: .yellow)
        }
    }
}

#Preview {
    SystemView().environmentObject(HealthModel())
}
