/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

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
    /// Command issued through UIKit or SwiftUI predicate-based instrumentation.
    case predicate
    /// Command issued through SwiftUI view modifiers-based instrumentation with view modifiers.
    case swiftui
    /// Command issued through manual instrumentation, originating from the `RUMMonitor` API.
    case manual

    /// The priority of this instrumentation. Higher values take precedence, allowing actions from one type to overwrite those
    /// from a lower-priority type (e.g., a SwiftUI button tap takes precedence over the touch on its containing UIKit table view cell).
    var priority: Int { rawValue }
}
