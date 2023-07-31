/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogTrace

/*
 NOTE: The casting methods defined here do shadow the ones defined in `Datadog.Casting`.
 The difference is that here in tests we do force unwrapping (`as!`), whereas in `Datadog` we do `as?` with a warning.

 This is needed for expressiveness in testing, where i.e. `XCTAssertNil(span.context.dd?.parentID)` may give a false positive
 without considering if the `parentID` is `nil`. Using `span.context.dd.parentID` mitigates it.
 */

internal extension OTTracer {
    var dd: DatadogTracer { self as! DatadogTracer }
}

internal extension OTSpan {
    var dd: DDSpan { self as! DDSpan }
}

internal extension OTSpanContext {
    var dd: DDSpanContext { self as! DDSpanContext }
}
