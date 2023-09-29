/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import DatadogInternal

public class CoreLoggerMock: CoreLogger {
    private let queue = DispatchQueue(label: "core-logger-mock")
    public private(set) var recordedLogs: [(level: CoreLoggerLevel, message: String, error: Error?)] = []

    public init() { }

    // MARK: - CoreLogger

    public func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?) {
        let newLog = (level, message(), error)
        queue.async { self.recordedLogs.append(newLog) }
    }

    public func reset() {
        queue.async { self.recordedLogs = [] }
    }

    // MARK: - Matching

    public typealias RecordedLog = (message: String, error: DDError?)

    private func recordedLogs(ofLevel level: CoreLoggerLevel) -> [RecordedLog] {
        return queue.sync {
            recordedLogs
                .filter({ $0.level == level })
                .map { ($0.message, $0.error.map({ DDError(error: $0) })) }
        }
    }

    public var debugLogs: [RecordedLog] { recordedLogs(ofLevel: .debug) }
    public var warnLogs: [RecordedLog] { recordedLogs(ofLevel: .warn) }
    public var errorLogs: [RecordedLog] { recordedLogs(ofLevel: .error) }
    public var criticalLogs: [RecordedLog] { recordedLogs(ofLevel: .critical) }

    public var debugLog: RecordedLog? { debugLogs.last }
    public var warnLog: RecordedLog? { warnLogs.last }
    public var errorLog: RecordedLog? { errorLogs.last }
    public var criticalLog: RecordedLog? { criticalLogs.last }
}

/// `Telemetry` recording sent telemetry.
public class TelemetryMock: Telemetry, CustomStringConvertible {
    public let expectation: XCTestExpectation?

    @ReadWriteLock
    public private(set) var messages: [TelemetryMessage] = []

    @ReadWriteLock
    public private(set) var description: String = "Telemetry logs:"

    public init(expectation: XCTestExpectation? = nil) {
        self.expectation = expectation
    }

    public func send(telemetry: DatadogInternal.TelemetryMessage) {
        messages.append(telemetry)

        switch telemetry {
        case .debug(_, let message, let attributes):
            let attributesString = attributes.map({ ", \($0)" }) ?? ""
            description.append("\n- [debug] \(message)" + attributesString)
        case .error(_, let message, let kind, let stack):
            description.append("\n - [error] \(message), kind: \(kind ?? "nil"), stack: \(stack ?? "nil")")
        case .configuration(let configuration):
            description.append("\n- [configuration] \(configuration)")
        case let .metric(name, attributes):
            let attributesString = attributes.map({ "\($0.key): \($0.value)" }).joined(separator: ", ")
            description.append("\n- [metric] '\(name)' (" + attributesString + ")")
        }
    }
}

public extension Array where Element == TelemetryMessage {
    /// Returns properties of the first metric message of given name.
    func firstMetric(named metricName: String) -> (name: String, attributes: [String: Encodable])? {
        return compactMap({ $0.asMetric }).filter({ $0.name == metricName }).first
    }

    /// Returns attributes of the first ERROR telemetry in this array.
    func firstError() -> (id: String, message: String, kind: String?, stack: String?)? {
        return compactMap { $0.asError }.first
    }
}

public extension TelemetryMessage {
    /// Extracts debug from telemetry message.
    var asDebug: (id: String, message: String, attributes: [String: Encodable]?)? {
        guard case let .debug(id, message, attributes) = self else {
            return nil
        }
        return (id: id, message: message, attributes: attributes)
    }

    /// Extracts debug from telemetry message.
    var asError: (id: String, message: String, kind: String?, stack: String?)? {
        guard case let .error(id, message, kind, stack) = self else {
            return nil
        }
        return (id: id, message: message, kind: kind, stack: stack)
    }

    /// Extracts configuration from telemetry message.
    var asConfiguration: ConfigurationTelemetry? {
        guard case let .configuration(configuration) = self else {
            return nil
        }
        return configuration
    }

    /// Extracts metric attributes if this is metric message.
    var asMetric: (name: String, attributes: [String: Encodable])? {
        guard case let .metric(name, attributes) = self else {
            return nil
        }
        return (name: name, attributes: attributes)
    }
}

extension DD {
    /// Syntactic sugar for patching the `dd` bundle by replacing `logger`.
    ///
    /// ```
    /// let dd = DD.mockWith(logger: CoreLoggerMock())
    /// defer { dd.reset() }
    /// ```
    public static func mockWith<CL: CoreLogger>(logger: CL) -> DDMock<CL> {
        let mock = DDMock(
            oldLogger: DD.logger,
            logger: logger
        )
        DD.logger = logger
        return mock
    }
}

public struct DDMock<CL: CoreLogger> {
    let oldLogger: CoreLogger

    public let logger: CL

    public func reset() {
        DD.logger = oldLogger
    }
}
