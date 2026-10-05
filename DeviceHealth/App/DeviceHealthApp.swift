import SwiftUI

@main
struct DeviceHealthApp: App {
    @StateObject private var health = HealthModel()
    @StateObject private var charge = ChargeMonitor()

    var body: some Scene {
        WindowGroup {
            TabView {
                HealthView()
                    .tabItem { Label("Health", systemImage: "heart.text.square") }
                ChargeView()
                    .tabItem { Label("Charging", systemImage: "bolt.batteryblock") }
            }
            .environmentObject(health)
            .environmentObject(charge)
        }
    }
}
