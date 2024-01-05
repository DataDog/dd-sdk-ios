/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

internal enum DatadogTagKeys: String {
    case spanKind = "span.kind"
    case errorMessage = "error.Message"
}

internal class OTelSpan: OpenTelemetryApi.Span {
    private var _status: OpenTelemetryApi.Status
    private var _name: String

    var attributes: [String: OpenTelemetryApi.AttributeValue]
    let context: OpenTelemetryApi.SpanContext
    var kind: OpenTelemetryApi.SpanKind
    let ddSpan: DDSpan
    let tracer: DatadogTracer
    let queue: DispatchQueue

    /// `isRecording` indicates whether the span is recording or not
    /// and events can be added to it.
    var isRecording: Bool

    var status: OpenTelemetryApi.Status {
        get {
            fatalError("Not implemented yet")
        }
        set {
            fatalError("Not implemented yet")
        }
    }

    /// `name` of the span is akin to operation name in Datadog
    var name: String {
        get {
            queue.sync {
                _name
            }
        }
        set {
            queue.sync {
                guard isRecording else {
                    return
                }
                _name = newValue
            }
            ddSpan.setOperationName(name)
        }
    }

    init(
        attributes: [String: OpenTelemetryApi.AttributeValue],
        kind: OpenTelemetryApi.SpanKind,
        name: String,
        parentSpanID: OpenTelemetryApi.SpanId?,
        spanContext: OpenTelemetryApi.SpanContext,
        spanKind: OpenTelemetryApi.SpanKind,
        startTime: Date,
        tracer: DatadogTracer
    ) {
        self._name = name
        self._status = .unset
        self.attributes = attributes
        self.context = spanContext
        self.kind = kind
        self.isRecording = true
        self.queue = tracer.queue
        self.tracer = tracer
        self.ddSpan = .init(
            tracer: tracer,
            context: .init(
                traceID: context.traceId.toDatadog(),
                spanID: context.spanId.toDatadog(),
                parentSpanID: parentSpanID?.toDatadog(),
                baggageItems: .init()
            ),
            operationName: name,
            startTime: startTime,
            tags: [:]
        )
    }

    // swiftlint:disable unavailable_function
    func addEvent(name: String) {
        fatalError("Not implemented yet")
    }

    func addEvent(name: String, timestamp: Date) {
        fatalError("Not implemented yet")
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {
        fatalError("Not implemented yet")
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {
        fatalError("Not implemented yet")
    }
    // swiftlint:enable unavailable_function

    func end() {
        end(time: Date())
    }

    func end(time: Date) {
        let semaphore = DispatchSemaphore(value: 0)
        var ended = false
        var tags: [String: String] = [:]

        queue.sync {
            guard isRecording else {
                ended = true
                semaphore.signal()
                return
            }
            isRecording = false
            tags = makeTags()
            semaphore.signal()
        }
        semaphore.wait()

        // if the span was already ended before, we don't want to end it again
        guard !ended else {
            return
        }

        // There is no need to lock here, because `DDSpan` is thread-safe
        for (key, value) in tags {
            ddSpan.setTag(key: key, value: value)
        }

        // SpanKind maps to the `span.kind` tag in Datadog
        ddSpan.setTag(key: DatadogTagKeys.spanKind.rawValue, value: kind.rawValue)
        ddSpan.finish(at: time)
    }

    private func makeTags() -> [String: String] {
        var tags = [String: String]()
        for (key, value) in attributes {
            switch value {
            case .string(let value):
                tags[key] = value
            case .bool(let value):
                tags[key] = value.description
            case .int(let value):
                tags[key] = value.description
            case .double(let value):
                tags[key] = value.description
            // swiftlint:disable unavailable_function
            case .stringArray:
                fatalError("Not implemented yet")
            case .boolArray:
                fatalError("Not implemented yet")
            case .intArray:
                fatalError("Not implemented yet")
            case .doubleArray:
                fatalError("Not implemented yet")
            case .set:
                fatalError("Not implemented yet")
            // swiftlint:enable unavailable_function
            }
        }
        return tags
    }

    var description: String {
        return "OTelSpan"
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {
        queue.sync {
            guard isRecording else {
                return
            }

            attributes[key] = value
        }
    }
}
