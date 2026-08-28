/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The Command Subscriber is able to process RUM Commands.
///
/// This protocol expect a single function to receive `RUMCommand`.
internal protocol RUMCommandSubscriber: AnyObject {
    /// Processes the given RUM Command.
    ///
    /// - Parameter command: The RUM command to process.
    func process(command: RUMCommand)
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
internal enum InstrumentationType: Int {
    /// Command issued through UIKit predicate-based instrumentation.
    case uikit
    /// Command issued through SwiftUI predicate-based instrumentation.
    case swiftuiAutomatic
    /// Command issued through SwiftUI-based instrumentation with view modifiers.
    case swiftui
    /// Command issued through manual instrumentation, originating from the `RUMMonitor` API.
    case manual
    /// Command issued through a Flutter-originated view, resolved from the `_dd.instrumentation_type` cross-platform attribute.
    case flutter
    /// Command issued through a React Native-originated view, resolved from the `_dd.instrumentation_type` cross-platform attribute.
    case reactNative
    /// Command issued through a Unity-originated view, resolved from the `_dd.instrumentation_type` cross-platform attribute.
    case unity
    /// Command issued through a Kotlin Multiplatform-originated view, resolved from the `_dd.instrumentation_type` cross-platform attribute.
    case kotlinMultiplatform

    /// The priority of this instrumentation. Higher values take precedence, allowing actions from one type to overwrite those
    /// from a lower-priority type (e.g., a SwiftUI button tap takes precedence over the touch on its containing UIKit table view cell).
    var priority: Int { rawValue }
}

internal extension InstrumentationType {
    /// Extracts the cross-platform instrumentation type from the `_dd.instrumentation_type` attribute, removing it from
    /// `attributes` so it never leaks into customer-visible view attributes.
    ///
    /// - Parameter attributes: The attributes to extract the value from.
    /// - Returns: The resolved `InstrumentationType`, or `nil` if the attribute is missing or holds an unrecognized value.
    static func extract(from attributes: inout [AttributeKey: AttributeValue]) -> InstrumentationType? {
        let rawValue: String? = attributes
            .removeValue(forKey: CrossPlatformAttributes.instrumentationType)?
            .dd.decode()

        switch rawValue {
        case "flutter": return .flutter
        case "react-native": return .reactNative
        case "unity": return .unity
        case "kotlin-multiplatform": return .kotlinMultiplatform
        default: return nil
        }
    }
}
