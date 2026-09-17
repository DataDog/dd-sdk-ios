/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

/// The Command Subscriber is able to process RUM Commands.
///
/// This protocol expect a single function to receive `RUMCommand`.
internal protocol RUMCommandSubscriber: AnyObject {
    /// Processes the given RUM Command.
    ///
    /// - Parameter command: The RUM command to process.
    func process(command: RUMCommand)
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { get }
}

internal extension RUMCommandSubscriber {
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { nil }

    /// Resolves work invoked synchronously inside a trustworthy UI-event
    /// handoff. Calls outside that bounded scope preserve the historical
    /// process-representative behavior.
    var currentExecutionTarget: RUMCommandTarget {
        guard let handoff = RUMContextHandoff.current(for: rumContextHandoffOwner) else {
            return .processRepresentative
        }
        if let viewID = handoff.rumContext?.viewID
            .flatMap(UUID.init(uuidString:))
            .map(RUMUUID.init(rawValue:)) {
            return .view(viewID)
        }
        if let sceneIdentifier = handoff.sceneIdentifier {
            return .scene(RUMSceneIdentifier(rawValue: sceneIdentifier))
        }
        return .processRepresentative
    }
}

/// Provides immutable RUM context snapshots for instrumentation that must hand
/// context to customer work before the asynchronous command pipeline catches up.
///
/// The primary example is `UIApplication.sendEvent(_:)`: a control in scene B
/// can synchronously create a URL request while scene A is still the exported
/// process representative. Looking up B's already-active view here avoids
/// carrying A's context into that request without making command processing
/// synchronous.
internal protocol RUMContextSnapshotProviding: AnyObject {
    func rumContextSnapshot(for target: RUMCommandTarget) -> RUMCoreContext?
    /// Returns the snapshot only if it still belongs to a live session at the
    /// time customer work is about to be dispatched. A nil date uses the
    /// provider's clock when an inherited task resumes.
    func rumContextSnapshot(for target: RUMCommandTarget, at date: Date?) -> RUMCoreContext?
}

extension RUMContextSnapshotProviding {
    func rumContextSnapshot(for target: RUMCommandTarget, at date: Date?) -> RUMCoreContext? {
        rumContextSnapshot(for: target)
    }
}

/// A Command Publisher is responsible for creating RUM Commands
/// to be processed by a `RUMCommandSubscriber`.
internal protocol RUMCommandPublisher: AnyObject {
    /// Lets a `RUMCommandSubscriber` subscribe to this Publisher.
    ///
    /// The given subscriber should be used to process any command created
    /// by this publisher.
    ///
    /// - Parameter subscriber: The RUM command subscriber.
    func publish(to subscriber: RUMCommandSubscriber)
}

/// Represents the type of instrumentation used to create different RUM commands.
internal enum InstrumentationType: Equatable {
    /// Command issued through UIKit predicate-based instrumentation.
    case uikit
    /// Command issued through SwiftUI predicate-based instrumentation.
    case swiftuiAutomatic
    /// Command issued through SwiftUI-based instrumentation with view modifiers.
    case swiftui
    /// Command issued through manual instrumentation, originating from the `RUMMonitor` API.
    case manual
    /// Command issued through a cross-platform SDK-originated view (e.g. Flutter, React Native, Unity, Kotlin Multiplatform),
    /// resolved from the `_dd.instrumentation_type` cross-platform attribute. The associated value is the raw string reported
    /// by the cross-platform SDK, forwarded verbatim - any non-empty value is accepted, there is no fixed set of recognized values.
    case crossPlatform(String)

    /// The priority of this instrumentation. Higher values take precedence, allowing actions from one type to overwrite those
    /// from a lower-priority type (e.g., a SwiftUI button tap takes precedence over the touch on its containing UIKit table view cell).
    var priority: Int {
        switch self {
        case .uikit: return 0
        case .swiftuiAutomatic: return 1
        case .swiftui: return 2
        case .manual: return 3
        case .crossPlatform: return 4
        }
    }
}

internal extension InstrumentationType {
    /// Extracts the cross-platform instrumentation type from the `_dd.instrumentation_type` attribute, removing it from
    /// `attributes` so it never leaks into customer-visible view attributes.
    ///
    /// - Parameter attributes: The attributes to extract the value from.
    /// - Returns: The resolved `InstrumentationType`, or `nil` if the attribute is missing or empty.
    static func extract(from attributes: inout [AttributeKey: AttributeValue]) -> InstrumentationType? {
        let rawValue: String? = attributes
            .removeValue(forKey: CrossPlatformAttributes.instrumentationType)?
            .dd.decode()

        guard let rawValue = rawValue, !rawValue.isEmpty else {
            return nil
        }

        return .crossPlatform(rawValue)
    }
}
