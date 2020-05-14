/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `SpanOutput` which saves spans to file.
internal struct SpanFileOutput: SpanOutput {
    let spanBuilder: SpanBuilder
    let fileWriter: FileWriter

    func write(ddspan: DDSpan, finishTime: Date) {
        do {
            let span = try spanBuilder.createSpan(from: ddspan, finishTime: finishTime)
            let envelope = SpanEnvelope(span: span, environment: spanBuilder.environment)
            fileWriter.write(value: envelope)
        } catch {
            userLogger.error("🔥 Failed to build span: \(error)")
        }
    }
}
