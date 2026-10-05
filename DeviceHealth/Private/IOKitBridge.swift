import Foundation
import Darwin

/// Thin runtime bridge to IOKit. The iOS SDK ships IOKit without public headers,
/// so every symbol is resolved with dlsym. Nothing here links against private
/// frameworks at build time, which keeps the project buildable with a stock Xcode.
enum IOKitBridge {
    typealias IOObject = UInt32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: type)
    }

    // MARK: - IORegistry

    private typealias ServiceMatchingFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias NameMatchingFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias GetMatchingServiceFn = @convention(c) (mach_port_t, UnsafeMutableRawPointer?) -> IOObject
    private typealias CreateCFPropertiesFn = @convention(c) (IOObject, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, CFAllocator?, UInt32) -> kern_return_t
    private typealias ObjectReleaseFn = @convention(c) (IOObject) -> kern_return_t

    private static let ioServiceMatching = sym("IOServiceMatching", as: ServiceMatchingFn.self)
    private static let ioServiceNameMatching = sym("IOServiceNameMatching", as: NameMatchingFn.self)
    private static let ioServiceGetMatchingService = sym("IOServiceGetMatchingService", as: GetMatchingServiceFn.self)
    private static let ioRegistryEntryCreateCFProperties = sym("IORegistryEntryCreateCFProperties", as: CreateCFPropertiesFn.self)
    private static let ioObjectRelease = sym("IOObjectRelease", as: ObjectReleaseFn.self)

    enum ReadResult {
        case success([String: Any])
        case serviceNotFound
        case accessDenied(kern_return_t)
        case unavailable
    }

    /// Reads every property of the first IOService matching `className`
    /// (falls back to name matching when no class matches).
    static func properties(forServiceClass className: String) -> ReadResult {
        guard let ioServiceMatching, let ioServiceGetMatchingService,
              let ioRegistryEntryCreateCFProperties, let ioObjectRelease else { return .unavailable }

        // IOServiceGetMatchingService consumes the matching dictionary, so the raw
        // +1 pointer is handed straight over without ever bridging it into ARC.
        var service: IOObject = 0
        if let matching = className.withCString({ ioServiceMatching($0) }) {
            service = ioServiceGetMatchingService(0, matching)
        }
        if service == 0, let ioServiceNameMatching,
           let matching = className.withCString({ ioServiceNameMatching($0) }) {
            service = ioServiceGetMatchingService(0, matching)
        }
        guard service != 0 else { return .serviceNotFound }
        defer { _ = ioObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        let kr = ioRegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
            return .accessDenied(kr)
        }
        return .success(dict)
    }

    // MARK: - IOPowerSources (semi-public, works inside the sandbox)

    private typealias CopyInfoFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias CopyListFn = @convention(c) (UnsafeRawPointer) -> UnsafeMutableRawPointer?
    private typealias GetDescriptionFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeMutableRawPointer?
    private typealias CopyAdapterFn = @convention(c) () -> UnsafeMutableRawPointer?

    private static let ioPSCopyPowerSourcesInfo = sym("IOPSCopyPowerSourcesInfo", as: CopyInfoFn.self)
    private static let ioPSCopyPowerSourcesList = sym("IOPSCopyPowerSourcesList", as: CopyListFn.self)
    private static let ioPSGetPowerSourceDescription = sym("IOPSGetPowerSourceDescription", as: GetDescriptionFn.self)
    private static let ioPSCopyExternalPowerAdapterDetails = sym("IOPSCopyExternalPowerAdapterDetails", as: CopyAdapterFn.self)

    /// The description dictionary of the internal battery as published by powerd.
    static func powerSourceDescription() -> [String: Any]? {
        guard let ioPSCopyPowerSourcesInfo, let ioPSCopyPowerSourcesList,
              let ioPSGetPowerSourceDescription,
              let infoPtr = ioPSCopyPowerSourcesInfo() else { return nil }
        let info = Unmanaged<CFTypeRef>.fromOpaque(infoPtr).takeRetainedValue()
        let infoRaw = Unmanaged.passUnretained(info).toOpaque()

        guard let listPtr = ioPSCopyPowerSourcesList(infoRaw) else { return nil }
        let list = Unmanaged<CFArray>.fromOpaque(listPtr).takeRetainedValue()

        for i in 0..<CFArrayGetCount(list) {
            guard let source = CFArrayGetValueAtIndex(list, i),
                  let descPtr = ioPSGetPowerSourceDescription(infoRaw, source) else { continue }
            let desc = Unmanaged<CFDictionary>.fromOpaque(descPtr).takeUnretainedValue()
            if let dict = desc as? [String: Any] { return dict }
        }
        return nil
    }

    /// Details of the currently attached power adapter (wired or wireless).
    static func externalPowerAdapterDetails() -> [String: Any]? {
        guard let ioPSCopyExternalPowerAdapterDetails,
              let ptr = ioPSCopyExternalPowerAdapterDetails() else { return nil }
        return Unmanaged<CFDictionary>.fromOpaque(ptr).takeRetainedValue() as? [String: Any]
    }
}
