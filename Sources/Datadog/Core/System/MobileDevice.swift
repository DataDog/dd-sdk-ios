import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Describes current mobile device.
internal struct MobileDevice {
    let model: String
    let osName: String
    let osVersion: String

    /// Returns `MobileDevice` if `UIKit` can be imported on current platform.
    /// For other platforms returns `nil`.
    static var current: MobileDevice? {
        #if canImport(UIKit)
        return MobileDevice(
            model: UIDevice.current.model,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion
        )
        #else
        return nil
        #endif
    }
}
