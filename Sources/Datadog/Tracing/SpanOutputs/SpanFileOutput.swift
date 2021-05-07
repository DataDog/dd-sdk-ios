/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `SpanOutput` which saves spans to file.
internal struct SpanFileOutput: SpanOutput {
    let fileWriter: Writer
    /// Environment to encode in span.
    let environment: String

    func write(span: SpanEvent) {
        let envelope = SpanEventsEnvelope(span: span, environment: environment)
        fileWriter.write(value: envelope)
    }
}
