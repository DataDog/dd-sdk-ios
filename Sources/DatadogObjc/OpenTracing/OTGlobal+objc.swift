/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@available(*, deprecated, renamed: "DDGlobal")
@objcMembers
@objc(OTGlobal)
public class OTGlobal: NSObject {
    @available(*, deprecated, message: "Use `DDGlobal.sharedTracer`.")
    public static func initSharedTracer(_ tracer: OTTracer) {
        guard let ddtracer = tracer.dd else {
            return
        }
        sharedTracer = ddtracer
    }

    public internal(set) static var sharedTracer: OTTracer {
        get { DDGlobal.sharedTracer }
        set { DDGlobal.sharedTracer = newValue }
    }
}
