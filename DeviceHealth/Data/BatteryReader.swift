import Foundation
import UIKit

/// Gathers battery + charger data from the deepest source available, falling back
/// to powerd's IOPowerSources and finally UIDevice.
@MainActor
enum BatteryReader {
    /// Registry classes tried in order. `IOPMPowerSource` is the base class, so it also
    /// matches the PMU charger driver (AppleARMPMUCharger) on iPhones.
    static let batteryServiceClasses = ["AppleSmartBattery", "IOPMPowerSource", "AppleARMPMUCharger"]

    static func snapshot() -> BatterySnapshot {
        var s = BatterySnapshot()

        // 1. Private registry
        var errors: [String] = []
        for cls in batteryServiceClasses {
            switch IOKitBridge.properties(forServiceClass: cls) {
            case .success(let props) where props["Voltage"] != nil || props["CurrentCapacity"] != nil:
                s.registryRaw = props
                s.registryClass = cls
            case .success:
                errors.append("\(cls): no battery keys")
            case .serviceNotFound:
                errors.append("\(cls): not found")
            case .accessDenied(let kr):
                errors.append("\(cls): denied (0x\(String(UInt32(bitPattern: kr), radix: 16)))")
            case .unavailable:
                errors.append("IOKit not loadable")
            }
            if s.registryClass != nil { break }
        }
        if s.registryClass == nil { s.registryError = errors.joined(separator: "\n") }

        // 2. IOPowerSources
        s.powerSourceRaw = IOKitBridge.powerSourceDescription() ?? [:]
        s.adapterDetailsRaw = IOKitBridge.externalPowerAdapterDetails() ?? [:]

        if !s.registryRaw.isEmpty {
            s.access = .full
            applyRegistry(Dict(s.registryRaw), to: &s)
        } else if !s.powerSourceRaw.isEmpty {
            s.access = .limited
        }
        applyPowerSource(Dict(s.powerSourceRaw), to: &s)
        if s.adapter.isEmpty, !s.adapterDetailsRaw.isEmpty {
            s.adapter = AdapterInfo(Dict(s.adapterDetailsRaw))
        }

        // 3. Public fallback
        applyUIDevice(to: &s)
        return s
    }

    private static func applyRegistry(_ d: Dict, to s: inout BatterySnapshot) {
        s.percent = d.int("CurrentCapacity")
        s.isCharging = d.bool("IsCharging")
        s.externalConnected = d.bool("ExternalConnected")
        s.externalChargeCapable = d.bool("ExternalChargeCapable")
        s.fullyCharged = d.bool("FullyCharged")

        s.voltage_mV = d.int(anyOf: "Voltage", "AppleRawBatteryVoltage")
        s.amperage_mA = d.int("Amperage")
        s.instantAmperage_mA = d.int("InstantAmperage")
        s.temperatureC = d.double("Temperature").map { $0 / 100 }
        s.virtualTemperatureC = d.double("VirtualTemperature").map { $0 / 100 }

        let bd = d.dict("BatteryData")
        s.cycleCount = d.int("CycleCount") ?? bd.int("CycleCount")
        s.designCapacity_mAh = d.int("DesignCapacity") ?? bd.int("DesignCapacity")
        s.nominalChargeCapacity_mAh = d.int("NominalChargeCapacity")
        s.rawMaxCapacity_mAh = d.int("AppleRawMaxCapacity")
        s.rawCurrentCapacity_mAh = d.int("AppleRawCurrentCapacity")
        s.maximumCapacityPercent = d.int(anyOf: "MaximumCapacityPercent") ?? bd.int("MaximumCapacityPercent")
        s.qmax_mAh = bd.ints("Qmax")
        s.weightedRa_mOhm = bd.int("WeightedRa")
        s.cellVoltages_mV = bd.ints("CellVoltage")
        s.chemID = bd.int("ChemID")
        s.batterySerial = d.string(anyOf: "Serial", "BatterySerialNumber")
        s.gasGaugeFirmware = d.string("GasGaugeFirmwareVersion")
        s.batteryManufacturer = d.string(anyOf: "Manufacturer", "DeviceName")
        s.lifetime = bd.dict("LifetimeData")

        s.adapter = AdapterInfo(d.dict("AdapterDetails"))
        s.charger = ChargerInfo(d.dict("ChargerData"))
        s.telemetry = PowerTelemetry(d.dict("PowerTelemetryData"))
    }

    private static func applyPowerSource(_ d: Dict, to s: inout BatterySnapshot) {
        guard !d.isEmpty else { return }
        if s.percent == nil, let cur = d.int("Current Capacity"), let max = d.int("Max Capacity"), max > 0 {
            s.percent = Int((Double(cur) / Double(max) * 100).rounded())
        }
        if s.isCharging == nil { s.isCharging = d.bool("Is Charging") }
        if s.fullyCharged == nil { s.fullyCharged = d.bool("Is Charged") }
        if s.externalConnected == nil { s.externalConnected = d.string("Power Source State") == "AC Power" }
        if s.voltage_mV == nil { s.voltage_mV = d.int("Voltage") }
        if s.amperage_mA == nil { s.amperage_mA = d.int("Current") }
        if s.temperatureC == nil, let t = d.double("Temperature") { s.temperatureC = t > 200 ? t / 100 : t }
        if let t = d.int("Time to Full Charge"), t >= 0 { s.timeToFull_min = t }
        if let t = d.int("Time to Empty"), t >= 0 { s.timeToEmpty_min = t }
    }

    private static func applyUIDevice(to s: inout BatterySnapshot) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if s.percent == nil, device.batteryLevel >= 0 {
            s.percent = Int((device.batteryLevel * 100).rounded())
        }
        let state = device.batteryState
        if s.externalConnected == nil { s.externalConnected = state == .charging || state == .full }
        if s.isCharging == nil { s.isCharging = state == .charging }
        if s.fullyCharged == nil { s.fullyCharged = state == .full }
    }
}
