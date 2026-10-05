import SwiftUI

/// Tab 3: live throughput and since-boot totals per interface.
struct NetworkView: View {
    @EnvironmentObject var model: HealthModel

    var body: some View {
        let n = model.network
        NavigationStack {
            List {
                InterfaceSection(title: "Wi-Fi", symbol: "wifi", tint: .blue,
                                 rate: model.wifiRate, totalIn: n.wifiIn, totalOut: n.wifiOut)
                InterfaceSection(title: "Cellular", symbol: "antenna.radiowaves.left.and.right", tint: .green,
                                 rate: model.cellRate, totalIn: n.cellIn, totalOut: n.cellOut)
                Section {
                    MetricRow("Downloaded", Fmt.diskBytes(n.wifiIn + n.cellIn), symbol: "arrow.down.circle.fill", tint: .teal)
                    MetricRow("Uploaded", Fmt.diskBytes(n.wifiOut + n.cellOut), symbol: "arrow.up.circle.fill", tint: .teal)
                } header: {
                    SectionHeader("All interfaces since boot", symbol: "sum", tint: .teal)
                } footer: {
                    Text("Since-boot totals come from 32-bit interface counters and wrap every 4 GB.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Network")
            .refreshable { model.refresh() }
        }
    }
}

private struct InterfaceSection: View {
    let title: String
    let symbol: String
    let tint: Color
    let rate: (rx: Double, tx: Double)
    let totalIn: UInt64
    let totalOut: UInt64

    var body: some View {
        Section {
            HStack(spacing: 12) {
                StatTile(title: "Download", value: Fmt.rate(rate.rx), unit: "",
                         symbol: "arrow.down", tint: tint)
                StatTile(title: "Upload", value: Fmt.rate(rate.tx), unit: "",
                         symbol: "arrow.up", tint: tint)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            MetricRow("Received since boot", Fmt.diskBytes(totalIn))
            MetricRow("Sent since boot", Fmt.diskBytes(totalOut))
        } header: {
            SectionHeader(title, symbol: symbol, tint: tint)
        }
    }
}

#Preview {
    NetworkView().environmentObject(HealthModel())
}
