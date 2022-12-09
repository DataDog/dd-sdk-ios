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
