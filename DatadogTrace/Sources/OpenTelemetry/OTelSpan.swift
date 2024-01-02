/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

class OTelSpan: OpenTelemetryApi.Span {
    private let tracer: DatadogTracer
    private let queue: DispatchQueue
    private var _status: OpenTelemetryApi.Status
    private var _name: String

    init(
        context: OpenTelemetryApi.SpanContext,
        kind: OpenTelemetryApi.SpanKind,
        name: String,
        tracer: DatadogTracer
    ) {
        self._name = name
        self._status = .unset
        self.context = context
        self.isRecording = true
        self.kind = kind
        self.queue = tracer.queue
        self.tracer = tracer
    }

    var kind: OpenTelemetryApi.SpanKind

    var context: OpenTelemetryApi.SpanContext

    var isRecording: Bool

    var status: OpenTelemetryApi.Status {
        get {
            queue.sync {
                _status
            }
        }
        set {
            queue.sync {
                _status = newValue
            }
        }
    }

    var name: String {
        get {
            queue.sync {
                _name
            }
        }
        set {
            queue.sync {
                _name = newValue
            }
        }
    }

    func addEvent(name: String) {
        fatalError("Not implemented")
    }

    func addEvent(name: String, timestamp: Date) {
        fatalError("Not implemented")
    }

    func addEvent(name: String, attributes: [String : OpenTelemetryApi.AttributeValue]) {
        fatalError("Not implemented")
    }

    func addEvent(name: String, attributes: [String : OpenTelemetryApi.AttributeValue], timestamp: Date) {
        fatalError("Not implemented")
    }

    func end() {
        fatalError("Not implemented")
    }

    func end(time: Date) {
        fatalError("Not implemented")
    }

    var description: String {
        return "WrapperSpan"
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {
        fatalError("Not implemented")
    }
}
