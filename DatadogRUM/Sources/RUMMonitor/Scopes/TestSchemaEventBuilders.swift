/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// PROTOTYPE ONLY — DO NOT MERGE TO MAIN
// Phase 2.3: Backend schema validation prototype.
// Sends test events to staging in 3 schema variants so the backend team can
// measure query performance against each format before making a schema decision.
// Remove this file (and the sendTestOption* calls in MemoryTimeseriesCollector) before Phase 3 merge.

import Foundation
import DatadogInternal

// MARK: - Test-only timeseries name values

/// Test-only name values — not in production TimeseriesName enum (which is code-generated).
private enum TestTimeseriesName: String {
    case testSchemaANumber = "test_schema_a_number"
    case testSchemaAString = "test_schema_a_string"
    case testSchemaB       = "test_schema_b"
    case testSchemaC       = "test_schema_c"
}

// MARK: - Option A: Typed sub-field (nested data_point object)

/// Data point for Option A: nested object with typed sub-fields.
/// Encodes as { "data_point": { "number": <double|null>, "string": <string|null> }, "timestamp": <int64> }
private struct TestOptionADataPoint: Encodable {
    struct InnerDataPoint: Encodable {
        let number: Double?
        let string: String?
    }

    let dataPoint: InnerDataPoint
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case dataPoint = "data_point"
        case timestamp
    }
}

// MARK: - Option B: Flat mixed-type value (same field, different JSON types)

/// Data point for Option B: flat field that carries either Double or String.
/// Encodes as { "data_point_value": <double|string>, "timestamp": <int64> }
private struct TestOptionBDataPoint: Encodable {
    enum Value {
        case number(Double)
        case string(String)
    }

    let value: Value
    let timestamp: Int64

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timestamp, forKey: .timestamp)
        switch value {
        case .number(let d): try c.encode(d, forKey: .dataPointValue)
        case .string(let s): try c.encode(s, forKey: .dataPointValue)
        }
    }

    enum CodingKeys: String, CodingKey {
        case dataPointValue = "data_point_value"
        case timestamp
    }
}

// MARK: - Option C: Compound object with semantic named fields

/// Data point for Option C: compound object with semantic named fields.
/// Encodes as { "data_point": { "memory_max": <double>, "memory_percent": <double> }, "timestamp": <int64> }
private struct TestOptionCDataPoint: Encodable {
    struct InnerDataPoint: Encodable {
        let memoryMax: Double
        let memoryPercent: Double

        enum CodingKeys: String, CodingKey {
            case memoryMax = "memory_max"
            case memoryPercent = "memory_percent"
        }
    }

    let dataPoint: InnerDataPoint
    let timestamp: Int64

    enum CodingKeys: String, CodingKey {
        case dataPoint = "data_point"
        case timestamp
    }
}

// MARK: - Parallel Timeseries structs (one per option)

/// Timeseries wrapper for Option A data points.
private struct TestTimeseriesOptionA: Encodable {
    let data: [TestOptionADataPoint]
    let end: Int64
    let id: String
    let name: String
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case data
        case end
        case id
        case name
        case start
    }
}

/// Timeseries wrapper for Option B data points.
private struct TestTimeseriesOptionB: Encodable {
    let data: [TestOptionBDataPoint]
    let end: Int64
    let id: String
    let name: String
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case data
        case end
        case id
        case name
        case start
    }
}

/// Timeseries wrapper for Option C data points.
private struct TestTimeseriesOptionC: Encodable {
    let data: [TestOptionCDataPoint]
    let end: Int64
    let id: String
    let name: String
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case data
        case end
        case id
        case name
        case start
    }
}

// MARK: - Parallel outer event structs (one per option)

/// Outer RUM event wrapper for Option A, mirroring RUMTimeseriesEvent but with TestTimeseriesOptionA.
private struct TestEventOptionA: Encodable {
    let dd: DD
    let application: Application
    let date: Int64
    let session: Session
    let source: String
    let timeseries: TestTimeseriesOptionA
    let type: String = "timeseries"
    let view: String? = nil

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application
        case date
        case session
        case source
        case timeseries
        case type
        case view
    }

    struct DD: Encodable {
        let formatVersion: Int64 = 2
        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    struct Application: Encodable {
        let id: String
    }

    struct Session: Encodable {
        let id: String
        let type: String
    }
}

/// Outer RUM event wrapper for Option B, mirroring RUMTimeseriesEvent but with TestTimeseriesOptionB.
private struct TestEventOptionB: Encodable {
    let dd: TestEventOptionA.DD
    let application: TestEventOptionA.Application
    let date: Int64
    let session: TestEventOptionA.Session
    let source: String
    let timeseries: TestTimeseriesOptionB
    let type: String = "timeseries"
    let view: String? = nil

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application
        case date
        case session
        case source
        case timeseries
        case type
        case view
    }
}

/// Outer RUM event wrapper for Option C, mirroring RUMTimeseriesEvent but with TestTimeseriesOptionC.
private struct TestEventOptionC: Encodable {
    let dd: TestEventOptionA.DD
    let application: TestEventOptionA.Application
    let date: Int64
    let session: TestEventOptionA.Session
    let source: String
    let timeseries: TestTimeseriesOptionC
    let type: String = "timeseries"
    let view: String? = nil

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application
        case date
        case session
        case source
        case timeseries
        case type
        case view
    }
}

// MARK: - Shared validation logging helper

/// Logs JSON encoding of a test event for first-flush schema validation.
/// Accepts any Encodable so it works with all 3 option types.
internal func logTestEventJSON<T: Encodable>(_ event: T, label: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(event)
        if let json = String(data: data, encoding: .utf8) {
            DD.logger.debug("Test schema event JSON [\(label)]:\n\(json)")
        }
    } catch {
        DD.logger.error("Failed to encode test event [\(label)]: \(error)")
    }
}

// MARK: - Send functions (called from MemoryTimeseriesCollector.flushEvents)

/// Sends Option A test events to the writer: two events (one for _number, one for _string).
/// Option A encodes data points as { "data_point": { "number": <double|null>, "string": <string|null> } }.
///
/// - Parameters:
///   - sessionID: RUM session identifier
///   - applicationID: Application identifier
///   - date: Event date in ms from epoch
///   - writer: Writer for sending events to DatadogCore
///   - logFirstEvent: Set to false after first log to avoid log spam (passed by reference)
internal func sendTestOptionA(
    sessionID: RUMUUID,
    applicationID: String,
    date: Int64,
    writer: Writer,
    logFirstEvent: inout Bool
) {
    let now = Date().timeIntervalSince1970.dd.toInt64Milliseconds
    let stringValues = ["charging", "discharging", "full"]

    let numberDataPoints = (0..<5).map { i in
        TestOptionADataPoint(
            dataPoint: .init(number: Double.random(in: 100_000_000...500_000_000), string: nil),
            timestamp: (now + Int64(i) * 1_000) * 1_000_000
        )
    }

    let stringDataPoints = (0..<5).map { i in
        TestOptionADataPoint(
            dataPoint: .init(number: nil, string: stringValues.randomElement()!),
            timestamp: (now + Int64(i) * 1_000) * 1_000_000
        )
    }

    let startNs = numberDataPoints.first!.timestamp
    let endNs = numberDataPoints.last!.timestamp

    let numberEvent = TestEventOptionA(
        dd: .init(),
        application: .init(id: applicationID),
        date: date,
        session: .init(id: sessionID.toRUMDataFormat, type: "user"),
        source: "ios",
        timeseries: TestTimeseriesOptionA(
            data: numberDataPoints,
            end: endNs,
            id: UUID().uuidString.lowercased(),
            name: TestTimeseriesName.testSchemaANumber.rawValue,
            start: startNs
        )
    )

    let stringStartNs = stringDataPoints.first!.timestamp
    let stringEndNs = stringDataPoints.last!.timestamp

    let stringEvent = TestEventOptionA(
        dd: .init(),
        application: .init(id: applicationID),
        date: date,
        session: .init(id: sessionID.toRUMDataFormat, type: "user"),
        source: "ios",
        timeseries: TestTimeseriesOptionA(
            data: stringDataPoints,
            end: stringEndNs,
            id: UUID().uuidString.lowercased(),
            name: TestTimeseriesName.testSchemaAString.rawValue,
            start: stringStartNs
        )
    )

    if logFirstEvent {
        logTestEventJSON(numberEvent, label: "option_a_number")
        logTestEventJSON(stringEvent, label: "option_a_string")
        logFirstEvent = false
    }

    writer.write(value: numberEvent)
    writer.write(value: stringEvent)
}

/// Sends Option B test events to the writer: one event with alternating Double/String data points.
/// Option B encodes data points as { "data_point_value": <double|string> } (flat, mixed types).
///
/// - Parameters:
///   - sessionID: RUM session identifier
///   - applicationID: Application identifier
///   - date: Event date in ms from epoch
///   - writer: Writer for sending events to DatadogCore
///   - logFirstEvent: Set to false after first log to avoid log spam (passed by reference)
internal func sendTestOptionB(
    sessionID: RUMUUID,
    applicationID: String,
    date: Int64,
    writer: Writer,
    logFirstEvent: inout Bool
) {
    let now = Date().timeIntervalSince1970.dd.toInt64Milliseconds
    let stringValues = ["charging", "discharging", "full"]

    // Alternate between Double and String values across 5 data points
    let dataPoints = (0..<5).map { i -> TestOptionBDataPoint in
        let ts = (now + Int64(i) * 1_000) * 1_000_000
        if i % 2 == 0 {
            return TestOptionBDataPoint(value: .number(Double.random(in: 100_000_000...500_000_000)), timestamp: ts)
        } else {
            return TestOptionBDataPoint(value: .string(stringValues.randomElement()!), timestamp: ts)
        }
    }

    let startNs = dataPoints.first!.timestamp
    let endNs = dataPoints.last!.timestamp

    let event = TestEventOptionB(
        dd: .init(),
        application: .init(id: applicationID),
        date: date,
        session: .init(id: sessionID.toRUMDataFormat, type: "user"),
        source: "ios",
        timeseries: TestTimeseriesOptionB(
            data: dataPoints,
            end: endNs,
            id: UUID().uuidString.lowercased(),
            name: TestTimeseriesName.testSchemaB.rawValue,
            start: startNs
        )
    )

    if logFirstEvent {
        logTestEventJSON(event, label: "option_b")
        logFirstEvent = false
    }

    writer.write(value: event)
}

/// Sends Option C test events to the writer: one event with compound semantic data points.
/// Option C encodes data points as { "data_point": { "memory_max": <double>, "memory_percent": <double> } }.
///
/// - Parameters:
///   - sessionID: RUM session identifier
///   - applicationID: Application identifier
///   - date: Event date in ms from epoch
///   - writer: Writer for sending events to DatadogCore
///   - logFirstEvent: Set to false after first log to avoid log spam (passed by reference)
internal func sendTestOptionC(
    sessionID: RUMUUID,
    applicationID: String,
    date: Int64,
    writer: Writer,
    logFirstEvent: inout Bool
) {
    let now = Date().timeIntervalSince1970.dd.toInt64Milliseconds

    let dataPoints = (0..<5).map { i in
        TestOptionCDataPoint(
            dataPoint: .init(
                memoryMax: Double.random(in: 100_000_000...500_000_000),
                memoryPercent: Double.random(in: 0...100)
            ),
            timestamp: (now + Int64(i) * 1_000) * 1_000_000
        )
    }

    let startNs = dataPoints.first!.timestamp
    let endNs = dataPoints.last!.timestamp

    let event = TestEventOptionC(
        dd: .init(),
        application: .init(id: applicationID),
        date: date,
        session: .init(id: sessionID.toRUMDataFormat, type: "user"),
        source: "ios",
        timeseries: TestTimeseriesOptionC(
            data: dataPoints,
            end: endNs,
            id: UUID().uuidString.lowercased(),
            name: TestTimeseriesName.testSchemaC.rawValue,
            start: startNs
        )
    )

    if logFirstEvent {
        logTestEventJSON(event, label: "option_c")
        logFirstEvent = false
    }

    writer.write(value: event)
}
