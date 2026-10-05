import Foundation
import UIKit

/// How much of the power stack the app could actually read on this install.
enum AccessLevel: String {
    /// Full AppleSmartBattery / PMU registry properties (TrollStore, jailbreak, or a lenient sandbox).
    case full = "Full registry access"
    /// Only powerd's IOPowerSources view (works in a normal sandboxed sideload).
    case limited = "Limited (IOPowerSources only)"
    /// Only UIDevice public battery API.
    case minimal = "Public API only"
}

enum ConnectionType: Equatable {
    case none
    case wired(String)      // detail, e.g. "USB Power Delivery"
    case magSafe
    case wireless(String)   // Qi / Qi2 / unknown wireless

    var title: String {
        switch self {
        case .none: return "Not connected"
        case .wired(let d): return "Wired · \(d)"
        case .magSafe: return "MagSafe"
        case .wireless(let d): return "Wireless · \(d)"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "bolt.slash"
        case .wired: return "cable.connector"
        case .magSafe: return "magsafe.batterypack"
        case .wireless: return "wave.3.right"
        }
    }

    var isConnected: Bool { self != .none }
}

struct PDProfile: Identifiable, Hashable {
    let index: Int
    let maxVoltage_mV: Int
    let maxCurrent_mA: Int
    var id: Int { index }
    var watts: Double { Double(maxVoltage_mV) * Double(maxCurrent_mA) / 1_000_000 }
}

struct AdapterInfo {
    var watts: Int?
    var current_mA: Int?
    var voltage_mV: Int?
    var name: String?
    var manufacturer: String?
    var model: String?
    var serial: String?
    var firmwareVersion: String?
    var hardwareVersion: String?
    var isWireless: Bool?
    var description: String?
    var familyCode: Int?
    var pdProfiles: [PDProfile] = []
    var activeProfileIndex: Int?
    var raw: [String: Any] = [:]

    init(_ d: Dict) {
        raw = d.raw
        watts = d.int("Watts")
        current_mA = d.int(anyOf: "Current", "AdapterCurrent")
        voltage_mV = d.int(anyOf: "AdapterVoltage", "Voltage")
        name = d.string("Name")
        manufacturer = d.string(anyOf: "Manufacturer", "Vendor")
        model = d.string("Model")
        serial = d.string(anyOf: "SerialString", "SerialNumber", "Serial")
        firmwareVersion = d.string(anyOf: "FwVersion", "FirmwareVersion")
        hardwareVersion = d.string(anyOf: "HwVersion", "HardwareVersion")
        isWireless = d.bool("IsWireless")
        description = d.string("Description")
        familyCode = d.int("FamilyCode")
        activeProfileIndex = d.int("UsbHvcHvcIndex")
        pdProfiles = d.dicts("UsbHvcMenu").compactMap { p in
            guard let v = p.int("MaxVoltage"), let i = p.int("MaxCurrent") else { return nil }
            return PDProfile(index: p.int("Index") ?? 0, maxVoltage_mV: v, maxCurrent_mA: i)
        }
    }

    var isEmpty: Bool { raw.isEmpty }
}

struct ChargerInfo {
    var chargingCurrent_mA: Int?
    var chargingVoltage_mV: Int?
    var notChargingReason: Int?
    var slowChargingReason: Int?
    var vacVoltageLimit_mV: Int?
    var timeChargingThermallyLimited: Int?
    var chargerID: Int?
    var raw: [String: Any] = [:]

    init(_ d: Dict) {
        raw = d.raw
        chargingCurrent_mA = d.int("ChargingCurrent")
        chargingVoltage_mV = d.int("ChargingVoltage")
        notChargingReason = d.int("NotChargingReason")
        slowChargingReason = d.int("SlowChargingReason")
        vacVoltageLimit_mV = d.int("VacVoltageLimit")
        timeChargingThermallyLimited = d.int("TimeChargingThermallyLimited")
        chargerID = d.int("ChargerID")
    }
}

struct PowerTelemetry {
    var systemPowerIn_mW: Int?
    var systemCurrentIn_mA: Int?
    var systemVoltageIn_mV: Int?
    var batteryPower_mW: Int?
    var systemLoad_mW: Int?
    var adapterEfficiencyLoss_mW: Int?
    var wallEnergyEstimate: Int?
    var raw: [String: Any] = [:]

    init(_ d: Dict) {
        raw = d.raw
        systemPowerIn_mW = d.int("SystemPowerIn")
        systemCurrentIn_mA = d.int("SystemCurrentIn")
        systemVoltageIn_mV = d.int("SystemVoltageIn")
        batteryPower_mW = d.int("BatteryPower")
        systemLoad_mW = d.int("SystemLoad")
        adapterEfficiencyLoss_mW = d.int("AdapterEfficiencyLoss")
        wallEnergyEstimate = d.int("WallEnergyEstimate")
    }
}

struct BatterySnapshot {
    var timestamp = Date()
    var access: AccessLevel = .minimal
    var registryClass: String?
    var registryError: String?

    // State
    var percent: Int?
    var isCharging: Bool?
    var externalConnected: Bool?
    var externalChargeCapable: Bool?
    var fullyCharged: Bool?
    var timeToFull_min: Int?
    var timeToEmpty_min: Int?

    // Electrical
    var voltage_mV: Int?
    var amperage_mA: Int?
    var instantAmperage_mA: Int?
    var cellVoltages_mV: [Int] = []

    // Thermal
    var temperatureC: Double?
    var virtualTemperatureC: Double?

    // Health
    var cycleCount: Int?
    var designCapacity_mAh: Int?
    var nominalChargeCapacity_mAh: Int?
    var rawMaxCapacity_mAh: Int?
    var rawCurrentCapacity_mAh: Int?
    var maximumCapacityPercent: Int?
    var qmax_mAh: [Int] = []
    var weightedRa_mOhm: Int?
    var chemID: Int?
    var batterySerial: String?
    var gasGaugeFirmware: String?
    var batteryManufacturer: String?
    var lifetime: Dict = Dict(nil)

    // Charging hardware
    var adapter = AdapterInfo(Dict(nil))
    var charger = ChargerInfo(Dict(nil))
    var telemetry = PowerTelemetry(Dict(nil))

    // Raw sources (for the explorer)
    var registryRaw: [String: Any] = [:]
    var powerSourceRaw: [String: Any] = [:]
    var adapterDetailsRaw: [String: Any] = [:]

    // MARK: Derived

    /// Battery health as iOS Settings reports it, best effort.
    var healthPercent: Double? {
        if let m = maximumCapacityPercent, m > 0 { return Double(m) }
        guard let design = designCapacity_mAh, design > 0 else { return nil }
        if let nominal = nominalChargeCapacity_mAh, nominal > 0 { return Double(nominal) / Double(design) * 100 }
        if let raw = rawMaxCapacity_mAh, raw > 0 { return Double(raw) / Double(design) * 100 }
        return nil
    }

    /// Measured power flowing in from the charger (PMU telemetry).
    var inputWatts: Double? { telemetry.systemPowerIn_mW.map { Double($0) / 1000 } }
    var inputAmps: Double? { telemetry.systemCurrentIn_mA.map { Double($0) / 1000 } }
    var inputVolts: Double? { telemetry.systemVoltageIn_mV.map { Double($0) / 1000 } }

    /// Power going into (+) or out of (−) the battery cell.
    var batteryWatts: Double? {
        guard let v = voltage_mV, let a = amperage_mA else { return nil }
        return Double(v) * Double(a) / 1_000_000
    }
    var batteryAmps: Double? { amperage_mA.map { Double($0) / 1000 } }
    var batteryVolts: Double? { voltage_mV.map { Double($0) / 1000 } }

    /// What the phone itself is drawing (input minus what goes into the battery).
    var systemLoadWatts: Double? {
        if let l = telemetry.systemLoad_mW { return Double(l) / 1000 }
        if let i = inputWatts, let b = batteryWatts { return i - b }
        return nil
    }

    var connection: ConnectionType {
        guard externalConnected == true else { return .none }
        let text = [adapter.name, adapter.description, adapter.model]
            .compactMap { $0?.lowercased() }.joined(separator: " ")
        if adapter.isWireless == true || text.contains("wireless") || text.contains("magsafe") || text.contains("qi") {
            if text.contains("magsafe") { return .magSafe }
            if text.contains("qi2") { return .wireless("Qi2") }
            if adapter.isWireless == true, let w = adapter.watts, w > 7 { return .magSafe }
            return .wireless(text.contains("qi") ? "Qi" : "Inductive")
        }
        if !adapter.pdProfiles.isEmpty || text.contains("pd") { return .wired("USB Power Delivery") }
        if text.contains("usb host") || text.contains("computer") { return .wired("USB host / computer") }
        if text.contains("usb") { return .wired("USB") }
        if adapter.isEmpty { return .wired("Unknown") }
        return .wired(adapter.description ?? adapter.name ?? "Adapter")
    }

    var chargeStateText: String {
        guard externalConnected == true else { return "On battery" }
        if fullyCharged == true { return "Fully charged" }
        if isCharging == true { return "Charging" }
        if let r = charger.notChargingReason, r != 0 {
            return "Connected, not charging (reason 0x\(String(r, radix: 16)))"
        }
        return "Connected, not charging (held / optimized)"
    }
}

/// Lifetime temperatures are tenths of a degree on some firmwares and whole degrees on others.
func normalizeLifetimeTemp(_ v: Int?) -> Double? {
    guard let v else { return nil }
    return abs(v) > 150 ? Double(v) / 10 : Double(v)
}
