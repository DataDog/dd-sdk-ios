/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public final class FeatureScopeMock: FeatureScope, @unchecked Sendable {
    private struct EventWriterMock: Writer {
        weak var scope: FeatureScopeMock?
        let bypassConsent: Bool

        func write<T, M>(value: T, metadata: M?) where T: Encodable, M: Encodable {
            scope?._events.mutate { $0.append((value, metadata, bypassConsent)) }
        }
    }

    @ReadWriteLock
    public var contextMock: DatadogContext
    @ReadWriteLock
    private var events: [(event: Encodable, metadata: Encodable?, bypassConsent: Bool)] = []
    @ReadWriteLock
    private var messages: [FeatureMessage] = []
    public let dataStore: DataStore

    /// Waits asynchronously until at least `count` events have been written.
    public func waitForWrittenEvents(count: Int, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while events.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    public init(
        context: DatadogContext = .mockAny(),
        dataStore: DataStore = DataStoreMock()
    ) {
        self.contextMock = context
        self.dataStore = dataStore
    }

    public func eventWriteContext(bypassConsent: Bool) async -> (DatadogContext, Writer)? {
        return (contextMock, EventWriterMock(scope: self, bypassConsent: bypassConsent))
    }

    public func context() async -> DatadogContext? {
        contextMock
    }

    public var telemetry: Telemetry { telemetryMock }

    public func send(message: FeatureMessage) {
        messages.append(message)
    }
    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        contextMock.set(additionalContext: context())
    }

    public func set(anonymousId: String?) {
        self.anonymousId = anonymousId
    }

    // MARK: - Side Effects Observation

    /// Retrieve anonymous events written through Even Write Context API.
    public var eventsWritten: [Encodable] { events.map { $0.event } }

    /// Retrieve typed events written through Even Write Context API.
    public func eventsWritten<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        return events.compactMap { $0.event as? T }
    }

    // swiftlint:disable function_default_parameter_at_end
    /// Retrieve typed events written through Even Write Context API with given `bypassConsent` flag.
    public func eventsWritten<T>(
        ofType type: T.Type = T.self,
        withBypassConsent bypassConsent: Bool
    ) -> [T] where T: Encodable {
        return events.filter { $0.bypassConsent == bypassConsent }.compactMap { $0.event as? T }
    }
    // swiftlint:enable function_default_parameter_at_end

    /// Retrieve data written in Data Store.
    public var dataStoreMock: DataStoreMock {
        guard let dataStoreMock = dataStore as? DataStoreMock else {
            preconditionFailure("FeatureScopeMock initialized with a non-DataStoreMock store")
        }
        return dataStoreMock
    }

    /// Retrieve telemetries sent to Telemetry endpoint.
    public let telemetryMock = TelemetryMock()

    /// Retrieve messages sent over Message Bus.
    public func messagesSent() -> [FeatureMessage] {
        return messages
    }

    /// Retrieve last set anonymous ID.
    public private(set) var anonymousId: String?
}
