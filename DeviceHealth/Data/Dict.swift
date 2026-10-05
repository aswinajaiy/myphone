import Foundation

/// Loosely-typed accessors for IORegistry / CF property dictionaries.
struct Dict {
    let raw: [String: Any]

    init(_ raw: [String: Any]?) { self.raw = raw ?? [:] }

    var isEmpty: Bool { raw.isEmpty }

    func int(_ key: String) -> Int? {
        switch raw[key] {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    func double(_ key: String) -> Double? {
        switch raw[key] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch raw[key] {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["yes", "true", "1"].contains(s.lowercased())
        default: return nil
        }
    }

    func string(_ key: String) -> String? {
        switch raw[key] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let d as Data:
            // Some vendor strings are published as NUL-terminated data blobs.
            let trimmed = d.prefix { $0 != 0 }
            return String(data: trimmed, encoding: .utf8)
        default: return nil
        }
    }

    func dict(_ key: String) -> Dict { Dict(raw[key] as? [String: Any]) }

    func ints(_ key: String) -> [Int] {
        (raw[key] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
    }

    func dicts(_ key: String) -> [Dict] {
        (raw[key] as? [Any])?.compactMap { ($0 as? [String: Any]).map(Dict.init) } ?? []
    }

    /// First non-nil integer among several candidate keys (key names drift between iOS releases).
    func int(anyOf keys: String...) -> Int? {
        for key in keys { if let v = int(key) { return v } }
        return nil
    }

    func string(anyOf keys: String...) -> String? {
        for key in keys { if let v = string(key) { return v } }
        return nil
    }
}
