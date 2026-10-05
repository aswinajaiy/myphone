import Foundation
import Darwin

/// Runtime access to libMobileGestalt's MGCopyAnswer.
/// Unprotected keys work in any app; protected keys (serial, UDID, ...) return nil
/// unless the binary carries `com.apple.private.MobileGestalt.AllowedProtectedKeys`.
enum MobileGestalt {
    private typealias CopyAnswerFn = @convention(c) (CFString, CFDictionary?) -> UnsafeMutableRawPointer?

    private static let copyAnswer: CopyAnswerFn? = {
        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW),
              let ptr = dlsym(handle, "MGCopyAnswer") else { return nil }
        return unsafeBitCast(ptr, to: CopyAnswerFn.self)
    }()

    static func answer(_ key: String) -> Any? {
        guard let copyAnswer, let ptr = copyAnswer(key as CFString, nil) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(ptr).takeRetainedValue()
    }

    static func string(_ key: String) -> String? {
        switch answer(key) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
