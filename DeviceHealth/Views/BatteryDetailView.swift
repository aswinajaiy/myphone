import SwiftUI
import UIKit

/// Full battery breakdown, pushed from the Overview battery card.
struct BatteryDetailView: View {
    @EnvironmentObject var model: HealthModel

    var body: some View {
        List {
            AccessBanner(snapshot: model.battery)
            BatteryHealthSection(b: model.battery)
            BatteryElectricalSection(b: model.battery)
            BatteryLifetimeSection(b: model.battery)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Battery")
        .refreshable { model.refresh() }
    }
}

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
            SectionHeader("Battery health", symbol: "heart.fill", tint: .pink)
        }
    }
}

private struct BatteryElectricalSection: View {
    let b: BatterySnapshot

    var body: some View {
        Section {
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
        } header: {
            SectionHeader("Battery right now", symbol: "bolt.fill", tint: .green)
        }
    }
}

private struct BatteryLifetimeSection: View {
    let b: BatterySnapshot

    var body: some View {
        let l = b.lifetime
        if !l.isEmpty {
            Section {
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
            } header: {
                SectionHeader("Battery lifetime", symbol: "clock.arrow.circlepath", tint: .indigo)
            }
        }
    }
}

#Preview {
    NavigationStack { BatteryDetailView() }.environmentObject(HealthModel())
}
