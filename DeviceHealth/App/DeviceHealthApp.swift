import SwiftUI

enum AppTab: Hashable {
    case overview, system, network, charging
}

@main
struct DeviceHealthApp: App {
    @StateObject private var health = HealthModel()
    @StateObject private var charge = ChargeMonitor()
    @State private var tab: AppTab = .overview

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                OverviewView(tab: $tab)
                    .tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(AppTab.overview)
                SystemView()
                    .tabItem { Label("System", systemImage: "cpu") }
                    .tag(AppTab.system)
                NetworkView()
                    .tabItem { Label("Network", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(AppTab.network)
                ChargeView()
                    .tabItem { Label("Charging", systemImage: "bolt.batteryblock") }
                    .tag(AppTab.charging)
            }
            .environmentObject(health)
            .environmentObject(charge)
        }
    }
}
