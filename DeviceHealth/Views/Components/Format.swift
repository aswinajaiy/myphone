import Foundation

enum Fmt {
    static let dash = "—"

    static func num(_ v: Double?, _ digits: Int = 2, _ unit: String = "") -> String {
        guard let v, v.isFinite else { return dash }
        let s = String(format: "%.\(digits)f", v)
        return unit.isEmpty ? s : "\(s) \(unit)"
    }

    static func int(_ v: Int?, _ unit: String = "") -> String {
        guard let v else { return dash }
        return unit.isEmpty ? "\(v)" : "\(v) \(unit)"
    }

    static func milli(_ v: Int?, _ unit: String, digits: Int = 3) -> String {
        num(v.map { Double($0) / 1000 }, digits, unit)
    }

    static func percent(_ v: Double?, digits: Int = 0) -> String {
        guard let v, v.isFinite else { return dash }
        return String(format: "%.\(digits)f%%", v)
    }

    static func bool(_ v: Bool?) -> String {
        guard let v else { return dash }
        return v ? "Yes" : "No"
    }

    static func str(_ v: String?) -> String {
        guard let v, !v.isEmpty else { return dash }
        return v
    }

    static func hex(_ v: Int?) -> String {
        guard let v else { return dash }
        return "0x" + String(UInt64(bitPattern: Int64(v)), radix: 16, uppercase: true)
    }

    static func bytes<T: BinaryInteger>(_ v: T) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory)
    }

    static func diskBytes<T: BinaryInteger>(_ v: T) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = t >= 86_400 ? [.day, .hour, .minute] : [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: t) ?? dash
    }

    static func minutes(_ m: Int?) -> String {
        guard let m else { return dash }
        return duration(TimeInterval(m * 60))
    }

    static func temp(_ c: Double?) -> String { num(c, 1, "°C") }
}
