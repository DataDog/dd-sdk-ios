/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
@testable import DatadogCore

/// A `DatadogCoreProtocol` which proxies all calls to the real `DatadogCore` implementation. It intercepts
/// all events written to the actual core and provides APIs to read their values back for tests.
///
/// Usage example:
///
///     ```
///     let core = DatadogCoreProxy(context: .mockWith(service: "foo-bar"))
///     defer { core.flushAndTearDown() }
///     core.register(feature: LoggingFeature.mockAny())
///
///     let logger = Logger.builder.build(in: core)
///     logger.debug("message")
///
///     let events = core.waitAndReturnEvents(of: LoggingFeature.self, ofType: LogEvent.self)
///     XCTAssertEqual(events[0].serviceName, "foo-bar")
///     ```
///
internal class DatadogCoreProxy: DatadogCoreProtocol {
    /// Counts references to `DatadogCoreProxy` instances, so we can prevent memory
    /// leaks of SDK core in `DatadogTestsObserver`.
    static var referenceCount = 0

    /// The SDK core managed by this proxy.
    private let core: DatadogCore

    private var featureScopeInterceptors: [String: FeatureScopeInterceptor] = [:]

    init(context: DatadogContext = .mockAny()) {
        self.context = context
        self.core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: context.trackingConsent,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: DatadogContextProvider(context: context),
            applicationVersion: context.version,
            backgroundTasksEnabled: .mockAny()
        )

        // override the message-bus's core instance
        core.bus.connect(core: self)
        DatadogCoreProxy.referenceCount += 1
    }

    deinit {
        DatadogCoreProxy.referenceCount -= 1
    }

    var context: DatadogContext {
        didSet {
            core.contextProvider.replace(context: context)
        }
    }

    func register<T>(feature: T) throws where T: DatadogFeature {
        featureScopeInterceptors[T.name] = FeatureScopeInterceptor()
        try core.register(feature: feature)
    }

    func get<T>(feature type: T.Type) -> T? where T: DatadogFeature {
        return core.get(feature: type)
    }

    func scope(for feature: String) -> FeatureScope? {
        return core.scope(for: feature).map { scope in
            FeatureScopeProxy(proxy: scope, interceptor: featureScopeInterceptors[feature]!)
        }
    }

    func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        core.set(baggage: baggage, forKey: key)
    }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        core.send(message: message, else: fallback)
    }
}

extension DatadogCoreProxy {
    func flushAndTearDown() {
        core.flushAndTearDown()

        if temporaryCoreDirectory.coreDirectory.exists() {
            temporaryCoreDirectory.coreDirectory.delete()
        }
        if temporaryCoreDirectory.osDirectory.exists() {
            temporaryCoreDirectory.osDirectory.delete()
        }
    }
}

extension DatadogCoreProxy: DispatchContinuation {
    func notify(_ continuation: @escaping () -> Void) {
        core.harvest.notify(continuation)
    }
}

private struct FeatureScopeProxy: FeatureScope {
    let proxy: FeatureScope
    let interceptor: FeatureScopeInterceptor

    func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
        proxy.eventWriteContext(bypassConsent: bypassConsent, forceNewBatch: forceNewBatch) { context, writer in
            try block(context, interceptor.intercept(writer: writer))
        }
    }
}

private class FeatureScopeInterceptor {
    struct InterceptingWriter: Writer {
        static let jsonEncoder = JSONEncoder.dd.default()

        let actualWriter: Writer
        unowned var interception: FeatureScopeInterceptor?

        func write<T: Encodable, M: Encodable>(value: T, metadata: M) {
            actualWriter.write(value: value, metadata: metadata)

            let event = value
            let data = try! InterceptingWriter.jsonEncoder.encode(value)
            interception?.events.append((event, data))
        }
    }

    func intercept(writer: Writer) -> Writer {
        return InterceptingWriter(actualWriter: writer, interception: self)
    }

    // MARK: - Synchronizing and awaiting events:

    @ReadWriteLock
    private(set) var events: [(event: Any, data: Data)] = []
}

extension DatadogCoreProxy {
    /// Returns all events of given type for certain Feature.
    /// - Parameters:
    ///   - name: The Feature to retrieve events from
    ///   - type: The type of events to filter out
    /// - Returns: A list of events.
    func waitAndReturnEvents<T>(ofFeature name: String, ofType type: T.Type) -> [T] where T: Encodable {
        waitDispatchContinuation()
        let interceptor = self.featureScopeInterceptors[name]
        return interceptor?.events.compactMap { $0.event as? T } ?? []
    }

    /// Returns serialized events of given Feature.
    ///
    /// - Parameter feature: The Feature to retrieve events from
    /// - Returns: A list of serialized events.
    func waitAndReturnEventsData(ofFeature name: String) -> [Data] {
        waitDispatchContinuation()
        let interceptor = self.featureScopeInterceptors[name]
        return interceptor?.events.map { $0.data } ?? []
    }
}
