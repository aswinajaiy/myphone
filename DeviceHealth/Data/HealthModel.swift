import Foundation
import Combine
import UIKit

@MainActor
final class HealthModel: ObservableObject {
    @Published private(set) var battery = BatterySnapshot()
    @Published private(set) var identity = DeviceIdentity()
    @Published private(set) var memory = MemoryStats()
    @Published private(set) var storage = StorageStats()
    @Published private(set) var cpuUser: Double?
    @Published private(set) var cpuSystem: Double?
    @Published private(set) var network = NetworkCounters()
    @Published private(set) var wifiRate: (rx: Double, tx: Double) = (0, 0)
    @Published private(set) var cellRate: (rx: Double, tx: Double) = (0, 0)
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var uptime = ProcessInfo.processInfo.systemUptime

    private var lastTicks: SystemInfo.CPUTicks?
    private var lastNetworkTime = Date()
    private var timer: AnyCancellable?

    init() {
        identity = SystemInfo.identity()
        network = SystemInfo.network()
        lastTicks = SystemInfo.cpuTicks()
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        battery = BatteryReader.snapshot()
        memory = SystemInfo.memory()
        storage = SystemInfo.storage()
        thermalState = ProcessInfo.processInfo.thermalState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        uptime = ProcessInfo.processInfo.systemUptime

        if let now = SystemInfo.cpuTicks() {
            if let last = lastTicks, let u = SystemInfo.cpuUsage(from: last, to: now) {
                cpuUser = u.user
                cpuSystem = u.system
            }
            lastTicks = now
        }

        let n = SystemInfo.network()
        let now = Date()
        let dt = now.timeIntervalSince(lastNetworkTime)
        if dt > 0 {
            func rate(_ a: UInt64, _ b: UInt64) -> Double { b >= a ? Double(b - a) / dt : 0 }
            wifiRate = (rate(network.wifiIn, n.wifiIn), rate(network.wifiOut, n.wifiOut))
            cellRate = (rate(network.cellIn, n.cellIn), rate(network.cellOut, n.cellOut))
        }
        network = n
        lastNetworkTime = now
    }
}
