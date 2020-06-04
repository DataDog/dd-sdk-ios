/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

/// Open Tracing [standard log fields](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#log-fields-table).
internal struct OpenTracingLogFields {
    static let message      = "message"
    static let event        = "event"
    static let errorKind    = "error.kind"
    static let stack        = "stack"

    // TODO: RUMM-477 Support more OT log fields
}

/// Open Tracing [tags](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#span-tags-table).
internal struct OpenTracingTagKeys {
    static let error        = "error"

    // TODO: RUMM-477 Support more OT tags
}
