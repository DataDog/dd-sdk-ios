/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import DatadogInternal

public class CoreLoggerMock: CoreLogger {
    @ReadWriteLock
    public private(set) var recordedLogs: [(level: CoreLoggerLevel, message: String, error: Error?)] = []

    public init() { }

    // MARK: - CoreLogger

    public func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?) {
        let newLog = (level, message(), error)
        recordedLogs.append(newLog)
    }

    public func reset() {
        recordedLogs = []
    }

    // MARK: - Matching

    public typealias RecordedLog = (message: String, error: DDError?)

    private func recordedLogs(ofLevel level: CoreLoggerLevel) -> [RecordedLog] {
        return recordedLogs
                .filter({ $0.level == level })
                .map { ($0.message, $0.error.map({ DDError(error: $0) })) }
    }

    public var debugLogs: [RecordedLog] { recordedLogs(ofLevel: .debug) }
    public var warnLogs: [RecordedLog] { recordedLogs(ofLevel: .warn) }
    public var errorLogs: [RecordedLog] { recordedLogs(ofLevel: .error) }
    public var criticalLogs: [RecordedLog] { recordedLogs(ofLevel: .critical) }

    public var debugMessages: [String] { debugLogs.map { $0.message } }
    public var warnMessages: [String] { warnLogs.map { $0.message } }
    public var errorMessages: [String] { errorLogs.map { $0.message } }
    public var criticalMessages: [String] { criticalLogs.map { $0.message } }

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
            description.append("\n - [error] \(message), kind: \(kind), stack: \(stack)")
        case .configuration(let configuration):
            description.append("\n- [configuration] \(configuration)")
        case let .metric(metric):
            let attributesString = metric.attributes.map({ "\($0.key): \($0.value)" }).joined(separator: ", ")
            description.append("\n- [metric] '\(metric.name)' (" + attributesString + ")")
        case .usage(let usage):
            description.append("\n- [usage] \(usage)")
        }
    }
}

public extension Array where Element == TelemetryMessage {
    /// Returns properties of the first metric message of given name.
    func firstMetric(named metricName: String) -> MetricTelemetry? {
        return compactMap({ $0.asMetric })
            .first(where: { $0.name == metricName })
    }

    /// Returns properties of the first metric message of given name.
    func lastMetric(named metricName: String) -> MetricTelemetry? {
        return compactMap({ $0.asMetric })
            .last(where: { $0.name == metricName })
    }

    /// Returns attributes of the first debug telemetry in this array.
    func firstDebug() -> (id: String, message: String, attributes: [String: Encodable]?)? {
        return compactMap { $0.asDebug }.first
    }

    /// Returns attributes of the first error telemetry in this array.
    func firstError() -> (id: String, message: String, kind: String?, stack: String?)? {
        return compactMap { $0.asError }.first
    }

    /// Returns the first configuration telemetry in this array.
    func firstConfiguration() -> ConfigurationTelemetry? {
        return compactMap { $0.asConfiguration }.first
    }
}

public extension TelemetryMessage {
    /// Extracts debug attributes from telemetry message.
    var asDebug: (id: String, message: String, attributes: [String: Encodable]?)? {
        guard case let .debug(id, message, attributes) = self else {
            return nil
        }
        return (id: id, message: message, attributes: attributes)
    }

    /// Extracts error attributes from telemetry message.
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
    var asMetric: MetricTelemetry? {
        guard case let .metric(metric) = self else {
            return nil
        }
        return metric
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
