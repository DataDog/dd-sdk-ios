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

        func write<T, M>(value: T, metadata: M?) where T : Encodable, M : Encodable {
            scope?.events.append((value, metadata, bypassConsent))
        }
    }

    @ReadWriteLock
    public var contextMock: DatadogContext
    @ReadWriteLock
    private var events: [(event: Encodable, metadata: Encodable?, bypassConsent: Bool)] = []
    @ReadWriteLock
    private var messages: [FeatureMessage] = []

    public init(context: DatadogContext = .mockAny()) {
        self.contextMock = context
    }

    public func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        block(contextMock, EventWriterMock(scope: self, bypassConsent: bypassConsent))
    }

    public func context(_ block: @escaping (DatadogContext) -> Void) {
        block(contextMock)
    }

    public var dataStore: DataStore { dataStoreMock }

    public var telemetry: Telemetry { telemetryMock }

    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        messages.append(message)
    }

    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        contextMock.baggages[key] = baggage()
    }

    // MARK: - Side Effects Observation

    /// Retrieve anonymous events written through Even Write Context API.
    public var eventsWritten: [Encodable] { events.map { $0.event } }

    /// Retrieve typed events written through Even Write Context API.
    public func eventsWritten<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        return events.compactMap { $0.event as? T }
    }

    /// Retrieve typed events written through Even Write Context API with given `bypassConsent` flag.
    public func eventsWritten<T>(ofType type: T.Type = T.self, withBypassConsent bypassConsent: Bool) -> [T] where T: Encodable {
        return events.filter { $0.bypassConsent == bypassConsent }.compactMap { $0.event as? T }
    }

    /// Retrieve data written in Data Store.
    public let dataStoreMock = DataStoreMock()

    /// Retrieve telemetries sent to Telemetry endpoint.
    public let telemetryMock = TelemetryMock()

    /// Retrieve messages sent over Message Bus.
    public func messagesSent() -> [FeatureMessage] {
        return messages
    }
}
