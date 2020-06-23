/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

/*
 NOTE: The casting methods defined here do shadow the ones defined in `Datadog.Casting`.
 The difference is that here in tests we do force unwrapping (`as!`), whereas in `Datadog` we do `as?` with a warning.

 This is needed for expressiveness in testing, where i.e. `XCTAssertNil(span.context.dd?.parentID)` may give a false positive
 without considering if the `parentID` is `nil`. Using `span.context.dd.parentID` mitigates it.
 */

// swiftlint:disable identifier_name
internal extension OpenTracing.Tracer {
    var dd: DDTracer { self as! DDTracer }
}

internal extension OpenTracing.Span {
    var dd: DDSpan { self as! DDSpan }
}

internal extension OpenTracing.SpanContext {
    var dd: DDSpanContext { self as! DDSpanContext }
}
// swiftlint:enable identifier_name
