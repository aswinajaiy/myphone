import SwiftUI

/// Formats arbitrary CF/IORegistry values for display.
enum RawFormat {
    static func scalar(_ value: Any) -> String {
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            if CFNumberIsFloatType(n as CFNumber) { return n.stringValue }
            let v = n.int64Value
            return abs(v) >= 0x10000 ? "\(v)  (0x\(String(UInt64(bitPattern: v), radix: 16, uppercase: true)))" : "\(v)"
        case let s as String:
            return "\"\(s)\""
        case let d as Data:
            let printable = d.allSatisfy { $0 == 0 || (0x20...0x7E).contains($0) }
            if printable, let s = String(data: d.prefix { $0 != 0 }, encoding: .ascii), !s.isEmpty {
                return "<\(s)>"
            }
            let hex = d.prefix(48).map { String(format: "%02x", $0) }.joined()
            return "<\(hex)\(d.count > 48 ? "…" : "")> (\(d.count) B)"
        case let date as Date:
            return date.formatted()
        case let a as [Any]:
            return "[\(a.count) items]"
        case let d as [String: Any]:
            return "{\(d.count) keys}"
        default:
            return String(describing: value)
        }
    }

    static func describe(_ value: Any, indent: String = "") -> String {
        let next = indent + "  "
        switch value {
        case let d as [String: Any]:
            let body = d.keys.sorted().map { "\(next)\($0) = \(describe(d[$0]!, indent: next))" }
            return "{\n" + body.joined(separator: "\n") + "\n\(indent)}"
        case let a as [Any]:
            let body = a.map { next + describe($0, indent: next) }
            return "(\n" + body.joined(separator: ",\n") + "\n\(indent))"
        default:
            return scalar(value)
        }
    }
}

struct RawExplorerView: View {
    let snapshot: BatterySnapshot

    /// Extra registry classes worth poking at. Add any class name you find interesting.
    static let extraClasses = [
        "AppleARMPMUCharger",
        "AppleSmartBattery",
        "AppleSmartBatteryManager",
        "IOPMrootDomain",
        "IOPlatformExpertDevice",
        "AppleHPMDevice",
        "IOAccessoryManager",
        "IOPortTransportStateUSB2",
        "AppleUSBHostPort",
        "AppleT8110USBXHCI",
        "AppleDialogSPMIPMU",
        "AppleSPMIPMU",
        "AppleInductiveChargingManager",
        "AppleMultiFunctionManager",
    ]

    var body: some View {
        List {
            Section("Battery snapshot sources") {
                link("Battery registry (\(snapshot.registryClass ?? "unavailable"))", snapshot.registryRaw)
                link("IOPowerSources description", snapshot.powerSourceRaw)
                link("External adapter details", snapshot.adapterDetailsRaw)
            }
            Section {
                ForEach(Self.extraClasses, id: \.self) { cls in
                    NavigationLink(cls) { RegistryClassView(className: cls) }
                }
            } header: {
                Text("Other IORegistry services")
            } footer: {
                Text("Classes vary by device and iOS version. Unreadable ones show the error returned.")
            }
        }
        .navigationTitle("Raw data")
    }

    @ViewBuilder
    private func link(_ title: String, _ dict: [String: Any]) -> some View {
        if dict.isEmpty {
            MetricRow(title, "empty")
        } else {
            NavigationLink { RawDictView(title: title, dict: dict) } label: {
                MetricRow(title, "\(dict.count) keys")
            }
        }
    }
}

private struct RegistryClassView: View {
    let className: String
    @State private var result: IOKitBridge.ReadResult?

    var body: some View {
        Group {
            switch result {
            case .success(let dict)?:
                RawDictView(title: className, dict: dict)
            case .serviceNotFound?:
                message("No service matching \(className) on this device.")
            case .accessDenied(let kr)?:
                message("Access denied (0x\(String(UInt32(bitPattern: kr), radix: 16))). Probably blocked by the sandbox.")
            case .unavailable?:
                message("IOKit could not be loaded.")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle(className)
        .task { result = IOKitBridge.properties(forServiceClass: className) }
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).padding()
    }
}

struct RawDictView: View {
    let title: String
    let dict: [String: Any]
    @State private var query = ""

    private var keys: [String] {
        let all = dict.keys.sorted()
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) ||
            RawFormat.scalar(dict[$0]!).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(keys, id: \.self) { key in
            RawValueRow(key: key, value: dict[key]!)
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: RawFormat.describe(dict))
        }
    }
}

private struct RawArrayView: View {
    let title: String
    let items: [Any]

    var body: some View {
        List(items.indices, id: \.self) { i in
            RawValueRow(key: "[\(i)]", value: items[i])
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RawValueRow: View {
    let key: String
    let value: Any

    var body: some View {
        if let d = value as? [String: Any] {
            NavigationLink { RawDictView(title: key, dict: d) } label: {
                MetricRow(key, RawFormat.scalar(d))
            }
        } else if let a = value as? [Any] {
            NavigationLink { RawArrayView(title: key, items: a) } label: {
                MetricRow(key, RawFormat.scalar(a))
            }
        } else {
            MetricRow(key, RawFormat.scalar(value))
        }
    }
}
