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
            RootTabView(tab: $tab)
                .environmentObject(health)
                .environmentObject(charge)
        }
    }
}

/// Tab bar on iPhone; on iOS 18+ it turns into a sidebar on wide windows (iPad, unfolded iPhone Duo).
private struct RootTabView: View {
    @Binding var tab: AppTab

    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab("Overview", systemImage: "gauge.with.dots.needle.67percent", value: AppTab.overview) {
                    OverviewView(tab: $tab)
                }
                Tab("System", systemImage: "cpu", value: AppTab.system) {
                    SystemView()
                }
                Tab("Network", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.network) {
                    NetworkView()
                }
                Tab("Charging", systemImage: "bolt.batteryblock", value: AppTab.charging) {
                    ChargeView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
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
        }
    }
}
