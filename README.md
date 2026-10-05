# Device Health

A personal iOS app that reads private IOKit / PMU data to show battery health and live charging power. It is not meant for the App Store.

There are two tabs:

1. **Health**: battery health, cycle count, Qmax, internal resistance, lifetime temperatures and currents, thermal state, CPU, memory, storage, network, device identity, display, and a raw IORegistry explorer.
2. **Charging**: live input watts, amps and volts from the charger; power going into the battery; how much the phone itself is drawing; wired, MagSafe or Qi detection; charger name, manufacturer, firmware and serial; USB‑PD profiles; charge controller targets and not‑charging reasons; a live chart; per‑session energy (Wh and mAh); CSV export.

## How much data you get depends on how it's installed

iOS hides most battery and charger data from sandboxed apps. The app tries the deepest source first and falls back from there. The yellow banner and the "Data source" row tell you which level you're on.

| Install method | Access level | What works |
|---|---|---|
| **TrollStore** (`.tipa`) or jailbreak | Full | Everything: registry battery data, PMU power telemetry, adapter details, protected MobileGestalt keys |
| Xcode / AltStore / Sideloadly sideload | Limited | Charge %, charging state, adapter rated watts and wireless flag (via `IOPSCopyExternalPowerAdapterDetails`), time to full or empty, plus all the CPU, memory, storage and network stats. Some `AppleSmartBattery` keys may come through depending on the iOS version. Use the Raw explorer to see what you actually get |
| (fallback) | Public only | `UIDevice` battery level and state |

TrollStore only installs on certain iOS versions (14.0–16.6.1 and 17.0 at the time of writing). On newer iOS without a jailbreak, the private entitlements in `Resources/TrollStore.entitlements` can't be used, and the app will run in **Limited** mode.

## Building

You need a Mac with Xcode 15 or later.

```sh
brew install xcodegen ldid
xcodegen generate            # creates DeviceHealth.xcodeproj
open DeviceHealth.xcodeproj  # set your team, run on device (Limited mode)
```

### TrollStore build

```sh
./scripts/build-tipa.sh      # -> build/DeviceHealth.tipa
```

AirDrop the `.tipa` to the phone and open it with TrollStore. Every push also builds the `.tipa` on GitHub Actions (`Build` workflow → artifact `DeviceHealth-tipa`), so you can grab it without a local build.

## Where the numbers come from

| Shown as | Source key | Notes |
|---|---|---|
| From charger (W/A/V) | `PowerTelemetryData.SystemPowerIn / SystemCurrentIn / SystemVoltageIn` | What the PMU measures coming in. This is the "how many watts am I getting" number |
| Into battery | `Voltage × Amperage` | Cell power. Negative means discharging |
| Phone is using | `PowerTelemetryData.SystemLoad`, or input − battery | |
| Conversion loss | `PowerTelemetryData.AdapterEfficiencyLoss` | |
| Charger rating, negotiated V/I | `AdapterDetails.Watts / AdapterVoltage / Current` | Negotiated limits, not actual flow |
| USB‑PD profiles | `AdapterDetails.UsbHvcMenu`, active = `UsbHvcHvcIndex` | |
| Wired / MagSafe / Qi | `AdapterDetails.IsWireless`, `Name`, `Description`, `UsbHvcMenu` | Heuristic. Wireless above 7.5 W is classed as MagSafe |
| Target charge current/voltage | `ChargerData.ChargingCurrent / ChargingVoltage` | |
| Not-charging reason | `ChargerData.NotChargingReason` | Raw bitfield. 0 means none |
| Health | `MaximumCapacityPercent`, or `NominalChargeCapacity ÷ DesignCapacity` | |
| Qmax, resistance, cell V | `BatteryData.Qmax / WeightedRa / CellVoltage` | |
| Lifetime stats | `BatteryData.LifetimeData.*` | Temperature units vary by firmware |
| Serial, UDID | MobileGestalt protected keys | TrollStore build only |

Key names change between iOS releases. If a row shows "—", open **Health → Advanced → Raw IORegistry explorer** to see what your device publishes, then map the key in `DeviceHealth/Data/BatteryReader.swift`.

## Removing things

Each section is its own small view. Delete its line from `body` in `Views/HealthView.swift` or `Views/ChargeView.swift`.

## Layout

```
DeviceHealth/
  App/DeviceHealthApp.swift      TabView
  Private/IOKitBridge.swift      dlsym bridge to IOKit + IOPowerSources
  Private/MobileGestalt.swift    MGCopyAnswer
  Data/BatteryReader.swift       registry → BatterySnapshot (with fallbacks)
  Data/BatterySnapshot.swift     typed model + derived values
  Data/SystemInfo.swift          sysctl / mach CPU, memory, storage, network
  Data/ChargeMonitor.swift       polling, history, session stats, CSV
  Data/HealthModel.swift         health tab refresh loop
  Views/…                        SwiftUI
Resources/TrollStore.entitlements
scripts/build-tipa.sh
```
