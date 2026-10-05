import Foundation
import UIKit
import Darwin
import os

struct MemoryStats {
    var total: UInt64 = 0
    var free: UInt64 = 0
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var appAvailable: UInt64 = 0
    var used: UInt64 { active + wired + compressed }
}

struct StorageStats {
    var total: Int64 = 0
    var available: Int64 = 0
    var availableImportant: Int64 = 0
    var availableOpportunistic: Int64 = 0
}

struct NetworkCounters {
    var wifiIn: UInt64 = 0
    var wifiOut: UInt64 = 0
    var cellIn: UInt64 = 0
    var cellOut: UInt64 = 0
}

struct DeviceIdentity {
    var machine = ""
    var marketingName: String?
    var modelNumber: String?
    var regionInfo: String?
    var serialNumber: String?
    var udid: String?
    var deviceColor: String?
    var cpuArchitecture: String?
    var chipID: String?
    var osVersion = ""
    var osBuild = ""
    var kernelVersion = ""
    var bootTime: Date?
}

@MainActor
enum SystemInfo {
    // MARK: sysctl

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    static func identity() -> DeviceIdentity {
        var id = DeviceIdentity()
        id.machine = sysctlString("hw.machine") ?? "?"
        id.osVersion = UIDevice.current.systemVersion
        id.osBuild = sysctlString("kern.osversion") ?? "?"
        id.kernelVersion = sysctlString("kern.version") ?? "?"
        id.bootTime = bootTime()
        id.marketingName = MobileGestalt.string("marketing-name")
        id.modelNumber = MobileGestalt.string("ModelNumber")
        id.regionInfo = MobileGestalt.string("RegionInfo")
        id.serialNumber = MobileGestalt.string("SerialNumber")
        id.udid = MobileGestalt.string("UniqueDeviceID")
        id.deviceColor = MobileGestalt.string("DeviceColor")
        id.cpuArchitecture = MobileGestalt.string("CPUArchitecture")
        id.chipID = MobileGestalt.string("ChipID")
        return id
    }

    // MARK: Memory

    static func memory() -> MemoryStats {
        var m = MemoryStats()
        m.total = ProcessInfo.processInfo.physicalMemory
        m.appAvailable = UInt64(os_proc_available_memory())

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let ps = UInt64(pageSize)
            m.free = UInt64(stats.free_count) * ps
            m.active = UInt64(stats.active_count) * ps
            m.inactive = UInt64(stats.inactive_count) * ps
            m.wired = UInt64(stats.wire_count) * ps
            m.compressed = UInt64(stats.compressor_page_count) * ps
        }
        return m
    }

    // MARK: CPU

    struct CPUTicks { var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0 }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0),
                        system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2),
                        nice: UInt64(info.cpu_ticks.3))
    }

    /// Returns (user, system, total) usage fractions between two tick samples.
    static func cpuUsage(from a: CPUTicks, to b: CPUTicks) -> (user: Double, system: Double, total: Double)? {
        let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
        let system = Double(b.system &- a.system)
        let idle = Double(b.idle &- a.idle)
        let all = user + system + idle
        guard all > 0 else { return nil }
        return (user / all, system / all, (user + system) / all)
    }

    // MARK: Storage

    static func storage() -> StorageStats {
        var s = StorageStats()
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityForOpportunisticUsageKey]
        if let v = try? url.resourceValues(forKeys: keys) {
            s.total = Int64(v.volumeTotalCapacity ?? 0)
            s.available = Int64(v.volumeAvailableCapacity ?? 0)
            s.availableImportant = v.volumeAvailableCapacityForImportantUsage ?? 0
            s.availableOpportunistic = v.volumeAvailableCapacityForOpportunisticUsage ?? 0
        }
        return s
    }

    // MARK: Network

    /// Interface byte counters since boot. These are 32-bit in if_data and wrap at 4 GiB.
    static func network() -> NetworkCounters {
        var n = NetworkCounters()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return n }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            let rx = UInt64(data.pointee.ifi_ibytes), tx = UInt64(data.pointee.ifi_obytes)
            if name.hasPrefix("en") {
                n.wifiIn += rx; n.wifiOut += tx
            } else if name.hasPrefix("pdp_ip") {
                n.cellIn += rx; n.cellOut += tx
            }
        }
        return n
    }
}
