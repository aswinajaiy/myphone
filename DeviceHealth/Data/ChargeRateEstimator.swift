import Foundation

/// Charging speed derived purely from how fast the charge % rises. Used when the
/// sandbox hides the battery's real current/voltage telemetry.
struct ChargeRateEstimate {
    let percentPerHour: Double
    /// Battery capacity the mAh/W figures are based on.
    let capacity_mAh: Int?
    /// True when `capacity_mAh` comes from the per-model table rather than the gas gauge.
    let capacityFromModelTable: Bool
    let timeToFull_min: Int?
    /// How much history the estimate covers.
    let window: TimeInterval
    /// Charge % gained across `window`.
    let percentGained: Int

    var mAhPerHour: Double? { capacity_mAh.map { percentPerHour / 100 * Double($0) } }

    /// Approximate power into the cell, assuming the typical Li-ion nominal voltage.
    var watts: Double? { mAhPerHour.map { $0 * ChargeRateEstimator.nominalVoltage / 1000 } }
}

struct ChargeRateEstimator {
    static let nominalVoltage = 3.85
    /// Only the most recent stretch is used so the rate tracks the charge curve.
    static let window: TimeInterval = 30 * 60

    /// Moments the charge % ticked up, oldest first.
    private var steps: [(time: Date, percent: Int)] = []
    private var lastPercent: Int?

    mutating func reset() {
        steps.removeAll()
        lastPercent = nil
    }

    mutating func update(percent: Int?, isCharging: Bool, at time: Date) {
        guard isCharging, let p = percent else {
            reset()
            return
        }
        if let last = lastPercent {
            if p > last {
                steps.append((time, p))
            } else if p < last {
                // Charge dropped (e.g. heavy use while plugged in) — start over.
                steps.removeAll()
            }
        }
        lastPercent = p

        // Trim to the window but keep at least two steps so there's always a rate.
        let cutoff = time.addingTimeInterval(-Self.window)
        while steps.count > 2, let first = steps.first, first.time < cutoff {
            steps.removeFirst()
        }
    }

    /// Needs two observed % ticks: the first tick's timing is unknown within its percent,
    /// so measuring between ticks avoids that offset.
    func estimate(now: Date, currentPercent: Int?, capacity_mAh: Int?, machine: String) -> ChargeRateEstimate? {
        guard steps.count >= 2, let first = steps.first, let last = steps.last else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= 30 else { return nil }
        let gained = Double(last.percent - first.percent)

        // If the next tick is overdue, charging has slowed (e.g. Optimized Charging hold),
        // so cap the rate by the best case for the time elapsed so far.
        let observed = gained / span
        let upperBound = (gained + 1) / now.timeIntervalSince(first.time)
        let perSecond = min(observed, upperBound)
        guard perSecond > 0 else { return nil }
        let perHour = perSecond * 3600

        let capacity = capacity_mAh ?? Self.designCapacity[machine]
        let ttf = currentPercent.map { p in max(0, Int((Double(100 - p) / perHour * 60).rounded())) }

        return ChargeRateEstimate(percentPerHour: perHour,
                                  capacity_mAh: capacity,
                                  capacityFromModelTable: capacity_mAh == nil && capacity != nil,
                                  timeToFull_min: ttf,
                                  window: now.timeIntervalSince(first.time),
                                  percentGained: last.percent - first.percent)
    }

    /// Published design capacities (mAh) by hardware identifier, for when the gas gauge isn't readable.
    static let designCapacity: [String: Int] = [
        "iPhone14,7": 3279, "iPhone14,8": 4325, "iPhone15,2": 3200, "iPhone15,3": 4323,
        "iPhone15,4": 3349, "iPhone15,5": 4383, "iPhone16,1": 3274, "iPhone16,2": 4422,
        "iPhone17,1": 3582, "iPhone17,2": 4685, "iPhone17,3": 3561, "iPhone17,4": 4674,
        "iPhone17,5": 3961,
    ]
}

extension BatterySnapshot {
    /// Whether real current/voltage readings are available (vs. % estimates only).
    var hasLiveTelemetry: Bool { inputWatts != nil || batteryWatts != nil }

    /// iOS's own time-to-full, ignoring the 0 / 65535 "still estimating" values.
    var reportedTimeToFull_min: Int? {
        guard let m = timeToFull_min, m > 0, m < 65535 else { return nil }
        return m
    }

    /// Reported time-to-full, falling back to the charge-rate estimate.
    func timeToFullEstimate(_ estimate: ChargeRateEstimate?) -> Int? {
        reportedTimeToFull_min ?? estimate?.timeToFull_min
    }
}

extension ChargeSample {
    func hasValue(for metric: ChartMetric) -> Bool {
        switch metric {
        case .watts: return inputW != nil || batteryW != nil
        case .amps: return inputA != nil || batteryA != nil
        case .volts: return inputV != nil || batteryV != nil
        case .temp: return tempC != nil
        case .percent: return percent != nil
        }
    }
}
