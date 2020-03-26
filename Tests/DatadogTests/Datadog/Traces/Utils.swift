/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
@testable import Datadog

// MARK: - OT to DD casting

// swiftlint:disable identifier_name
extension OpenTracing.SpanContext {
    var dd: DDSpanContext {
        return self as! DDSpanContext
    }
}
// swiftlint:enable identifier_name
