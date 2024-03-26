/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FeatureScopeMock: FeatureScope {
    struct EventWriterMock: Writer {
        weak var scope: FeatureScopeMock?

        func write<T, M>(value: T, metadata: M?) where T : Encodable, M : Encodable {
            scope?.events.append((value, metadata))
        }
    }

    @ReadWriteLock
    public var contextMock: DatadogContext
    @ReadWriteLock
    private var events: [(event: Encodable, metadata: Encodable?)] = []
    @ReadWriteLock
    private var messages: [FeatureMessage] = []

    public init(context: DatadogContext = .mockAny()) {
        self.contextMock = context
    }

    public func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        block(contextMock, EventWriterMock(scope: self))
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

    /// Retrieve events written through Even Write Context API.
    public func eventsWritten<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        return events.compactMap { $0.event as? T }
    }

    /// Retrieve data written in Data Store.
    public let dataStoreMock: DataStore = NOPDataStore()

    /// Retrieve telemetries sent to Telemetry endpoint.
    public let telemetryMock = TelemetryMock()

    /// Retrieve messages sent over Message Bus.
    public func messagesSent() -> [FeatureMessage] {
        return messages
    }
}
