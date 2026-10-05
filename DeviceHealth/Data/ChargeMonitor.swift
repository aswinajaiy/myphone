import Foundation
import Combine
import UIKit

struct ChargeSample: Identifiable {
    let time: Date
    let inputW: Double?
    let inputA: Double?
    let inputV: Double?
    let batteryW: Double?
    let batteryA: Double?
    let batteryV: Double?
    let tempC: Double?
    let percent: Int?
    var id: Date { time }
}

struct ChargeSession {
    let start: Date
    let startPercent: Int?
    var connection: ConnectionType
    var lastSample: Date
    var end: Date?
    var currentPercent: Int?
    var energyIn_Wh: Double = 0
    var energyIntoBattery_Wh: Double = 0
    var chargeIntoBattery_mAh: Double = 0
    var peakInputW: Double = 0
    var peakBatteryA: Double = 0
    var inputWSum: Double = 0
    var inputWCount = 0
    var maxTempC: Double?

    var isActive: Bool { end == nil }
    var duration: TimeInterval { (end ?? lastSample).timeIntervalSince(start) }
    var averageInputW: Double? { inputWCount > 0 ? inputWSum / Double(inputWCount) : nil }
    var percentGained: Int? {
        guard let a = startPercent, let b = currentPercent else { return nil }
        return b - a
    }
}

@MainActor
final class ChargeMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()
    @Published private(set) var samples: [ChargeSample] = []
    @Published private(set) var session: ChargeSession?
    @Published var interval: Double = 1 { didSet { restart() } }
    @Published var keepAwake = false { didSet { UIApplication.shared.isIdleTimerDisabled = keepAwake } }

    /// Rolling window kept for the charts and CSV export.
    var maxSamples = 7200

    private var timer: AnyCancellable?

    init() { start() }

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func restart() {
        stop()
        start()
    }

    func resetSession() {
        samples.removeAll()
        session = snapshot.connection.isConnected ? newSession(snapshot) : nil
    }

    private func newSession(_ s: BatterySnapshot) -> ChargeSession {
        ChargeSession(start: s.timestamp, startPercent: s.percent, connection: s.connection,
                      lastSample: s.timestamp, currentPercent: s.percent)
    }

    private func tick() {
        let s = BatteryReader.snapshot()
        snapshot = s

        samples.append(ChargeSample(time: s.timestamp, inputW: s.inputWatts, inputA: s.inputAmps, inputV: s.inputVolts,
                                    batteryW: s.batteryWatts, batteryA: s.batteryAmps, batteryV: s.batteryVolts,
                                    tempC: s.temperatureC, percent: s.percent))
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }

        updateSession(with: s)
    }

    private func updateSession(with s: BatterySnapshot) {
        let connected = s.connection.isConnected
        guard var cur = session, cur.isActive else {
            if connected { session = newSession(s) }
            return
        }
        if !connected {
            cur.end = s.timestamp
            session = cur
            return
        }

        let dtHours = s.timestamp.timeIntervalSince(cur.lastSample) / 3600
        cur.lastSample = s.timestamp
        cur.connection = s.connection
        cur.currentPercent = s.percent
        if let w = s.inputWatts {
            cur.energyIn_Wh += max(w, 0) * dtHours
            cur.peakInputW = max(cur.peakInputW, w)
            cur.inputWSum += w
            cur.inputWCount += 1
        }
        if let bw = s.batteryWatts, bw > 0 { cur.energyIntoBattery_Wh += bw * dtHours }
        if let ma = s.amperage_mA, ma > 0 { cur.chargeIntoBattery_mAh += Double(ma) * dtHours }
        if let a = s.batteryAmps { cur.peakBatteryA = max(cur.peakBatteryA, a) }
        if let t = s.temperatureC { cur.maxTempC = max(cur.maxTempC ?? t, t) }
        session = cur
    }

    func exportCSV() -> URL? {
        func f(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "" }
        let iso = ISO8601DateFormatter()
        var csv = "time,input_W,input_A,input_V,battery_W,battery_A,battery_V,temp_C,percent\n"
        for s in samples {
            csv += [iso.string(from: s.time), f(s.inputW), f(s.inputA), f(s.inputV),
                    f(s.batteryW), f(s.batteryA), f(s.batteryV), f(s.tempC),
                    s.percent.map(String.init) ?? ""].joined(separator: ",") + "\n"
        }
        let name = "charge-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
