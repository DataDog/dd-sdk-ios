/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct SpanCoreContext: Encodable {
    static let key = "span_context"

    enum CodingKeys: String, CodingKey {
        case traceID = "dd.trace_id"
        case spanID = "dd.span_id"
    }

    let traceID: String?
    let spanID: String?
}
