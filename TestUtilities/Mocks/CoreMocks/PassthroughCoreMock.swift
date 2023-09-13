/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import DatadogInternal

/// Passthrough core mocks feature-scope allowing recording events in **sync**.
///
/// The `DatadogCoreProtocol` implementation does not require any feature registration,
/// it will always provide a `FeatureScope` with the current context and a `writer` that will
/// store all events in the `events` property.
///
/// Usage:
///
///     let core = PassthroughCoreMock()
///     core.scope(for: "any-feature-name")?.eventWriteContext { context, writer in
///         // will always open a scope
///     }
///
/// The Passthrough core does not allow registering or retrieving a Feature instance.
///
///     let feature = MyCustomFeature()
///     try core.register(feature: feature)
///     core.get(feature: MyCustomFeature.self) // returns nil
///
open class PassthroughCoreMock: DatadogCoreProtocol, FeatureScope {
    /// Counts references to `PassthroughCoreMock` instances, so we can prevent memory
    /// leaks of SDK core in `DatadogTestsObserver`.
    public static var referenceCount = 0

    public static var onInit: (() -> Void)? = nil
    public static var onDeinit: (() -> Void)? = nil

    /// Current context that will be passed to feature-scopes.
    @ReadWriteLock
    public var context: DatadogContext {
        didSet { send(message: .context(context)) }
    }

    let writer = FileWriterMock()

    /// The message receiver.
    public var messageReceiver: FeatureMessageReceiver

    /// Test expectation that will be fullfilled when the `eventWriteContext` closure
    /// is executed.
    public var expectation: XCTestExpectation?

    /// Test expectation that will be fullfilled when the `eventWriteContext` closure
    /// is executed with `bypassConsent` parameter set to `true`.
    public var bypassConsentExpectation: XCTestExpectation?

    /// Test expectation that will be fullfilled when the `eventWriteContext` closure
    /// is executed with `forceNewBatch` parameter set to `true`.
    public var forceNewBatchExpectation: XCTestExpectation?

    /// Creates a Passthrough core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.
    ///   - expectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked.
    ///   - bypassConsentExpectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked with `bypassConsent` parameter set to `true`.
    ///   - forceNewBatchExpectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked with `forceNewBatch` parameter set to `true`.

    public required init(
        context: DatadogContext = .mockAny(),
        expectation: XCTestExpectation? = nil,
        bypassConsentExpectation: XCTestExpectation? = nil,
        forceNewBatchExpectation: XCTestExpectation? = nil,
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) {
        self.context = context
        self.expectation = expectation
        self.bypassConsentExpectation = bypassConsentExpectation
        self.forceNewBatchExpectation = forceNewBatchExpectation
        self.messageReceiver = messageReceiver

        messageReceiver.receive(message: .context(context), from: self)

        PassthroughCoreMock.onInit?()
        PassthroughCoreMock.referenceCount += 1
    }

    deinit {
        PassthroughCoreMock.referenceCount -= 1
        PassthroughCoreMock.onDeinit?()
    }

    /// no-op
    public func register<T>(feature: T) throws where T: DatadogFeature { }
    /// no-op
    public func get<T>(feature type: T.Type) -> T? where T: DatadogFeature { nil }

    /// Always returns a feature-scope.
    public func scope(for feature: String) -> FeatureScope? {
        self
    }

    public func set(feature: String, attributes: @escaping () -> FeatureBaggage) {
        context.featuresAttributes[feature] = attributes()
    }

    public func update(feature: String, attributes: @escaping () -> FeatureBaggage) {
        if context.featuresAttributes[feature] != nil {
            context.featuresAttributes[feature]?.merge(with: attributes())
        } else {
            context.featuresAttributes[feature] = attributes()
        }
    }

    public func send(message: FeatureMessage, else fallback: () -> Void) {
        if !messageReceiver.receive(message: message, from: self) {
            fallback()
        }
    }

    /// Execute `block` with the current context and a `writer` to record events.
    ///
    /// - Parameter block: The block to execute.
    public func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: (DatadogContext, Writer) throws -> Void) {
        XCTAssertNoThrow(try block(context, writer), "Encountered an error when executing `eventWriteContext`")
        expectation?.fulfill()

        if bypassConsent {
            bypassConsentExpectation?.fulfill()
        }

        if forceNewBatch {
            forceNewBatchExpectation?.fulfill()
        }
    }

    /// Recorded events from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    public var events: [Encodable] { writer.events }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.events(ofType: type)
    }
}
