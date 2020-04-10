/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
@testable import Datadog

// swiftlint:disable identifier_name
internal extension OpenTracing.Tracer {
    var dd: DDTracer { self as! DDTracer }
}

internal extension OpenTracing.Span {
    var dd: DDSpan { self as! DDSpan }
}
// swiftlint:enable identifier_name
