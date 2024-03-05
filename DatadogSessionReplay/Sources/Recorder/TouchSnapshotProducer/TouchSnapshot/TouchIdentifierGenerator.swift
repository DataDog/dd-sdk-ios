/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// Unique identifier of a touch.
/// It is used to mark `UITouch` objects in order to track their identity without capturing reference.
///
/// Ref.: https://developer.apple.com/documentation/uikit/uitouch
/// > If you need to store information about a touch outside of a multi-touch sequence, copy that information from the touch.
internal typealias TouchIdentifier = Int

/// Manages `TouchIdentifier` for `UITouch` instances.
///
/// The touch identifier is generated when `UITouch` "begans". It persists throughout its "moved" phase and gets removed
/// upon its "end" or "cancellation". This corresponds to the touch lifecycle dictated by `UIKit`, where instances of `UITouch`
/// are recycled and reused.
///
/// **Note**: All `TouchIdentifierGenerator` APIs must be called on the main thread.
internal final class TouchIdentifierGenerator {
    /// Upper limit for generated IDs.
    /// After `currentID` reaches this limit, it will start from `0`.
    private let maxID: TouchIdentifier
    /// The next `TouchIdentifier` to assign.
    private var currentID: TouchIdentifier

    init(currentID: TouchIdentifier = 0, maxID: TouchIdentifier = .max) {
        self.currentID = currentID
        self.maxID = maxID
    }

    /// Returns the `TouchIdentifier` for given instance of `UITouch`.
    /// - Parameter touch: the `UITouch` object
    /// - Returns: the `TouchIdentifier` of queried instance.
    func touchIdentifier(for touch: UITouch) -> TouchIdentifier {
        switch touch.phase.dd {
        case .down:
            return persistNextID(in: touch)
        case .move:
            guard let persistedID = touch.identifier else {
                // It means the touch began before SR was enabled → persit next ID in this touch:
                return persistNextID(in: touch)
            }
            return persistedID
        case .up:
            guard let persistedID = touch.identifier else {
                // It means the touch began before SR was enabled → only return next ID as we know the touch is ending:
                return getNextID()
            }
            touch.identifier = nil
            return persistedID
        default:
            return persistNextID(in: touch)
        }
    }

    private func persistNextID(in touch: UITouch) -> TouchIdentifier {
        let newID = getNextID()
        touch.identifier = newID
        return newID
    }

    private func getNextID() -> NodeID {
        let nextID = currentID
        currentID = currentID < maxID ? (currentID + 1) : 0
        return nextID
    }
}

// MARK: - UIView tagging

fileprivate var associatedTouchIdentifierKey: UInt8 = 1

private extension UITouch {
    var identifier: TouchIdentifier? {
        set { objc_setAssociatedObject(self, &associatedTouchIdentifierKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        get { objc_getAssociatedObject(self, &associatedTouchIdentifierKey) as? TouchIdentifier }
    }
}
#endif
