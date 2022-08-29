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
internal final class PassthroughCoreMock: DatadogV1CoreProtocol, FeatureV1Scope {
    /// Current context that will be passed to feature-scopes.
    internal var context: DatadogV1Context?

    internal let writer = FileWriterMock()

    /// The message receiver.
    private let messageReceiver: FeatureMessageReceiver

    /// Test expectation that will be fullfilled when the `eventWriteContext` closure
    /// is executed.
    internal var expectation: XCTestExpectation?

    /// Creates a Passthrough core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.
    ///   - expectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked.
    init(
        context: DatadogV1Context = .mockAny(),
        expectation: XCTestExpectation? = nil,
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) {
        self.context = context
        self.expectation = expectation
        self.messageReceiver = messageReceiver
    }

    /// no-op
    func register<T>(feature instance: T?) { }

    /// Returns `nil`
    func feature<T>(_ type: T.Type) -> T? {
        return nil
    }

    /// Always returns a feature-scope.
    func scope<T>(for featureType: T.Type) -> FeatureV1Scope? {
        self
    }

    func send(message: FeatureMessage, else fallback: () -> Void) {
        if !messageReceiver.receive(message: message, from: self) {
            fallback()
        }
    }

    /// Execute `block` with the current context and a `writer` to record events.
    ///
    /// - Parameter block: The block to execute.
    func eventWriteContext(_ block: (DatadogContext, Writer) throws -> Void) {
        guard let context = context else {
            return XCTFail("PassthroughCoreMock missing context")
        }

        do {
            try block(.init(context), writer)
        } catch let error {
            XCTFail("Encountered an error when executing `eventWriteContext`: \(error)")
        }

        expectation?.fulfill()
    }

    /// Recorded events from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    var events: [Encodable] { writer.events }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.events(ofType: type)
    }
}
