/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if DD_SDK_COMPILED_FOR_TESTING
/// An observer which intercepts all calls to eventWriteContext. 
/// It intercepts all events written to the actual core and provides APIs to read their values back for tests.
/// It must be initialized after all features have been registered in the core.
///
/// Usage example:
///     ```
///     let core = Datadog.sdkInstance(named: CoreRegistry.defaultInstanceName)
///     defer { core.flushAndTearDown() }
///     core.register(feature: LoggingFeature.mockAny())
///     let observer = DatadogCoreProxy(core: core)
/// 
///     let logger = Logger.builder.build(in: core)
///     logger.debug("message")
///
///     let events = observer.waitAndReturnEvents(of: LoggingFeature.self, ofType: LogEvent.self)
///     XCTAssertEqual(events[0].serviceName, "foo-bar")
///     ```
///
public class DatadogCoreObserver {
    /// The SDK core managed by this observer.
    private let core: DatadogCoreProtocol

    private var featureScopeInterceptors: [String: FeatureScopeInterceptor] = [:]

    public init(core: DatadogCoreProtocol) {
        self.core = core

        register(featureName: "rum")
        register(featureName: "logging")
        register(featureName: "tracing")
        register(featureName: "session-replay")
    }

    func register(featureName: String) {
        if let scope = core.scope(for: featureName) {
            let interceptor = FeatureScopeInterceptor()
            featureScopeInterceptors[featureName] = interceptor
            if let ddCore = core as? DatadogCore {
                ddCore.scopeOverrides[featureName] = FeatureScopeProxy(proxy: scope, interceptor: interceptor)
            }
        }
    }

    /// Returns all events of given type for certain Feature.
    /// - Parameters:
    ///   - name: The Feature to retrieve events from
    ///   - type: The type of events to filter out
    /// - Returns: A list of events.
    public func waitAndReturnEvents<T>(ofFeature name: String, ofType type: T.Type) -> [T] where T: Encodable {
        flush()
        let interceptor = self.featureScopeInterceptors[name]!
        return interceptor.waitAndReturnEvents().compactMap { $0.event as? T }
    }

    /// Returns serialized events of given Feature.
    ///
    /// - Parameter feature: The Feature to retrieve events from
    /// - Returns: A list of serialized events.
    public func waitAndReturnEventsData(ofFeature name: String) -> [String] {
        flush()
        let interceptor = self.featureScopeInterceptors[name]!
        return interceptor.waitAndReturnEvents().compactMap { $0.data.base64EncodedString() }
    }
    
    /// Clears all events of a given Feature
    ///
    /// - Parameter feature: The Feature to delete events from
    public func waitAndDeleteEvents(ofFeature name: String) -> Void {
        let interceptor = self.featureScopeInterceptors[name]!
        interceptor.waitAndDeleteEvents()
    }
    
    func flush() {
        if let ddCore = core as? DatadogCore {
            ddCore.flush()
        }
    }
}

private struct FeatureScopeProxy: FeatureScope {
    func context(_ block: @escaping (DatadogInternal.DatadogContext) -> Void) {
        // not implemented
    }
    
    let proxy: FeatureScope
    let interceptor: FeatureScopeInterceptor

    func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        interceptor.enter()
        proxy.eventWriteContext(bypassConsent: bypassConsent, forceNewBatch: forceNewBatch) { context, writer in
            block(context, interceptor.intercept(writer: writer))
            interceptor.leave()
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
            NSLog(data.base64EncodedString())
            interception?.events.append((event, data))
        }
    }

    func intercept(writer: Writer) -> Writer {
        return InterceptingWriter(actualWriter: writer, interception: self)
    }

    // MARK: - Synchronizing and awaiting events:

    @ReadWriteLock
    private var events: [(event: Any, data: Data)] = []

    private let group = DispatchGroup()

    func enter() { group.enter() }
    func leave() { group.leave() }
    
    func waitAndDeleteEvents() -> Void {
        _ = group.wait(timeout: .distantFuture)
        events = []
    }

    func waitAndReturnEvents() -> [(event: Any, data: Data)] {
        _ = group.wait(timeout: .distantFuture)
        return events
    }
}
#endif
