#if canImport(UIKit)
import UIKit

/// Abstraction protocol to get device information on the current platform
public protocol DeviceProtocol {
    var model: String { get }
    var systemName: String { get }
    var systemVersion: String { get }
    var vendorIdentifier: UUID? { get }
}

#if canImport(WatchKit)
import WatchKit

extension WKInterfaceDevice: DeviceProtocol {
    public var vendorIdentifier: UUID? {
        if #available(watchOS 6.2, *) {
            identifierForVendor
        } else {
            nil
        }
    }
}
#else
extension UIDevice: DeviceProtocol {
    public var vendorIdentifier: UUID? { identifierForVendor }
}
#endif

public enum DeviceFactory {
    /// Get the current device
    public static var current: DeviceProtocol {
        #if canImport(WatchKit)
        WKInterfaceDevice.current()
        #else
        UIDevice.current
        #endif
    }
}
#endif
