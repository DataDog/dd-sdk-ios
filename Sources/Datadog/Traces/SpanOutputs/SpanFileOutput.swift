/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `SpanOutput` which saves spans to file.
internal struct SpanFileOutput: SpanOutput {
    func write(span: DDSpan, finishTime: Date) {
        // TODO: RUMM-298 Write spans to file
    }
}
