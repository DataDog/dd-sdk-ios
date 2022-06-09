/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

@testable import Datadog

/// Passthrough core mocks feature-scope allowing recording events in **sync**.
///
/// The `DatadogCoreProtocol` implementation does not require any feature registration,
/// it will always provide a `FeatureScope` with the current context and a `writer` that will
/// store all events in the `events` property..
internal final class PassthroughCoreMock: DatadogV1CoreProtocol, V1FeatureScope, Writer {
    /// Current context that will be passed to feature-scopes.
    internal var context: DatadogV1Context?

    /// Test expectation that will be fullfilled when the `eventWriteContext` closure
    /// is executed.
    internal var expectation: XCTestExpectation?

    /// Recorded events from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    internal private(set) var events: [Encodable] = []

    /// Creates a Passthrough core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.
    ///   - expectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked.
    init(
        context: DatadogV1Context = .mockAny(),
        expectation: XCTestExpectation? = nil
    ) {
        self.context = context
        self.expectation = expectation
    }

    /// no-op
    func register<T>(feature instance: T?) { }

    /// Returns `nil`
    func feature<T>(_ type: T.Type) -> T? {
        return nil
    }

    /// Always returns a feature-scope.
    func scope<T>(for featureType: T.Type) -> V1FeatureScope? {
        self
    }

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    func write<T>(value: T) where T: Encodable {
        events.append(value)
    }

    /// Execute `block` with the current context and a `writer` to record events.
    ///
    /// - Parameter block: The block to execute.
    func eventWriteContext(_ block: (DatadogV1Context, Writer) throws -> Void) {
        guard let context = context else {
            return XCTFail("PassthroughCoreMock missing context")
        }

        try? block(context, self)
        expectation?.fulfill()
    }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        events.compactMap { $0 as? T }
    }
}
