import SwiftUI
import Charts

enum ChartMetric: String, CaseIterable, Identifiable {
    case watts = "Watts"
    case amps = "Amps"
    case volts = "Volts"
    case temp = "Temp"
    case percent = "%"
    var id: String { rawValue }

    var unit: String {
        switch self {
        case .watts: return "W"
        case .amps: return "A"
        case .volts: return "V"
        case .temp: return "°C"
        case .percent: return "%"
        }
    }
}

struct ChargeChart: View {
    let samples: [ChargeSample]
    let metric: ChartMetric
    let window: TimeInterval

    private struct Point: Identifiable {
        let time: Date
        let value: Double
        let series: String
        var id: String { "\(series)-\(time.timeIntervalSince1970)" }
    }

    private var points: [Point] {
        let cutoff = (samples.last?.time ?? Date()).addingTimeInterval(-window)
        var out: [Point] = []
        for s in samples where s.time >= cutoff {
            func add(_ v: Double?, _ series: String) {
                if let v { out.append(Point(time: s.time, value: v, series: series)) }
            }
            switch metric {
            case .watts:
                add(s.inputW, "From charger")
                add(s.batteryW, "Into battery")
            case .amps:
                add(s.inputA, "From charger")
                add(s.batteryA, "Into battery")
            case .volts:
                add(s.inputV, "Input bus")
                add(s.batteryV, "Battery")
            case .temp:
                add(s.tempC, "Battery")
            case .percent:
                add(s.percent.map(Double.init), "Charge")
            }
        }
        return out
    }

    var body: some View {
        let pts = points
        if pts.isEmpty {
            Text("No data yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Chart(pts) { p in
                LineMark(x: .value("Time", p.time), y: .value(metric.unit, p.value))
                    .foregroundStyle(by: .value("Series", p.series))
                    .interpolationMethod(.monotone)
            }
            .chartYAxisLabel(metric.unit)
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
        }
    }
}
