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
public final class DatadogCoreProxy: DatadogCoreProtocol {
    /// Counts references to `DatadogCoreProxy` instances, so we can prevent memory
    /// leaks of SDK core in `DatadogTestsObserver`.
    public private(set) static var referenceCount = 0

    /// The SDK core managed by this proxy.
    private let core: DatadogCore

    @ReadWriteLock
    private var featureScopeInterceptors: [String: FeatureScopeInterceptor] = [:]

    public convenience init(context: DatadogContext = .mockAny()) {
        self.init(
            core: DatadogCore(
                directory: temporaryCoreDirectory,
                dateProvider: SystemDateProvider(),
                initialConsent: context.trackingConsent,
                performance: .mockAny(),
                httpClient: HTTPClientMock(),
                encryption: nil,
                contextProvider: DatadogContextProvider(
                    context: context
                ),
                applicationVersion: context.version,
                maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
                backgroundTasksEnabled: .mockAny()
            )
        )
    }

    public init(core: DatadogCore) {
        self.context = core.contextProvider.read()
        self.core = core

        // override the message-bus's core instance
        core.bus.connect(core: self)
        DatadogCoreProxy.referenceCount += 1
    }

    deinit {
        DatadogCoreProxy.referenceCount -= 1
    }

    public var context: DatadogContext {
        didSet {
#if DD_SDK_COMPILED_FOR_TESTING
            core.contextProvider.replace(context: context)
#endif
        }
    }

    public func register<T>(feature: T) throws where T: DatadogFeature {
        try core.register(feature: feature)
    }

    public func feature<T>(named name: String, type: T.Type) -> T? {
        return core.feature(named: name, type: type)
    }

    public func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        if featureScopeInterceptors[T.name] == nil {
            featureScopeInterceptors[T.name] = FeatureScopeInterceptor()
        }
        return FeatureScopeProxy(
            proxy: core.scope(for: featureType),
            interceptor: featureScopeInterceptors[T.name]!
        )
    }

    public func setUserInfo(
        id: String? = nil,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:]
    ) {
        core.setUserInfo(id: id, name: name, email: email, extraInfo: extraInfo)
    }

    public func addUserExtraInfo(
        _ newExtraInfo: [AttributeKey: AttributeValue?]
    ) {
        core.addUserExtraInfo(newExtraInfo)
    }

    public func setAccountInfo(
        id: String,
        name: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:]
    ) {
        core.setAccountInfo(id: id, name: name, extraInfo: extraInfo)
    }

    public func clearAccountInfo() {
        core.clearAccountInfo()
    }

    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        core.set(context: context)
    }

    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        core.send(message: message, else: fallback)
    }

    public func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        return try core.mostRecentModifiedFileAt(before: before)
    }
}

extension DatadogCoreProxy {
    public func flush() {
        core.flush()
    }

    public func flushAndTearDown() throws {
        core.flushAndTearDown()

        if temporaryCoreDirectory.coreDirectory.exists() {
            try temporaryCoreDirectory.coreDirectory.delete()
        }
        if temporaryCoreDirectory.osDirectory.exists() {
            try temporaryCoreDirectory.osDirectory.delete()
        }
    }
}

private struct FeatureScopeProxy: FeatureScope {
    let proxy: FeatureScope
    let interceptor: FeatureScopeInterceptor

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        interceptor.enter()
        proxy.eventWriteContext(bypassConsent: bypassConsent) { context, writer in
            block(context, interceptor.intercept(writer: writer))
            interceptor.leave()
        }
    }

    func context(_ block: @escaping (DatadogContext) -> Void) {
        interceptor.enter()
        proxy.context { context in
            block(context)
            interceptor.leave()
        }
    }

    var telemetry: Telemetry { proxy.telemetry }
    var dataStore: DataStore { proxy.dataStore }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        proxy.send(message: message, else: fallback)
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        proxy.set(context: context)
    }

    func set(anonymousId: String?) {
        proxy.set(anonymousId: anonymousId)
    }
}

private final class FeatureScopeInterceptor: @unchecked Sendable {
    struct InterceptingWriter: Writer {
        static let jsonEncoder = JSONEncoder.dd.default()

        let group: DispatchGroup
        let actualWriter: Writer
        unowned var interception: FeatureScopeInterceptor?

        func write<T: Encodable, M: Encodable>(value: T, metadata: M, completion: @escaping () -> Void) {
            group.enter()
            defer { group.leave() }

            actualWriter.write(value: value, metadata: metadata, completion: completion)

            let event = value
            let data = try! InterceptingWriter.jsonEncoder.encode(value)
            interception?.events.append((event, data))
        }
    }

    func intercept(writer: Writer) -> Writer {
        return InterceptingWriter(group: group, actualWriter: writer, interception: self)
    }

    // MARK: - Synchronizing and awaiting events:

    @ReadWriteLock
    private var events: [(event: Any, data: Data)] = []

    private let group = DispatchGroup()

    func enter() { group.enter() }
    func leave() { group.leave() }

    func waitAndReturnEvents(timeout: DispatchTime) -> [(event: Any, data: Data)] {
        _ = group.wait(timeout: timeout)
        return events
    }
}

extension DatadogCoreProxy {
    /// Returns all events of given type for certain Feature.
    /// - Parameters:
    ///   - name: The Feature to retrieve events from
    ///   - type: The type of events to filter out
    /// - Returns: A list of events.
    public func waitAndReturnEvents<T>(ofFeature name: String, ofType type: T.Type, timeout: DispatchTime = .distantFuture) -> [T] where T: Encodable {
        flush()
        guard let interceptor = self.featureScopeInterceptors[name] else {
            return [] // feature scope was not requested, so there's no interception
        }
        return interceptor.waitAndReturnEvents(timeout: timeout).compactMap { $0.event as? T }
    }

    /// Returns serialized events of given Feature.
    ///
    /// - Parameter feature: The Feature to retrieve events from
    /// - Returns: A list of serialized events.
    public func waitAndReturnEventsData(ofFeature name: String, timeout: DispatchTime = .distantFuture) -> [Data] {
        flush()
        guard let interceptor = self.featureScopeInterceptors[name] else {
            return [] // feature scope was not requested, so there's no interception
        }
        return interceptor.waitAndReturnEvents(timeout: timeout).map { $0.data }
    }
}
