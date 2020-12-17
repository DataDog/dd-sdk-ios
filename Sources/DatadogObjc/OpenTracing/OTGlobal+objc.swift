/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
public class DDGlobal: NSObject {
    public internal(set) static var tracer: OTTracer = noopTracer {
        didSet {
            // We must also set the Swift `Global.tracer`
            // as it's used internally by auto-instrumentation feature.
            if let ddTracer = tracer.dd?.swiftTracer {
                Global.sharedTracer = ddTracer
            }
        }
    }
    public internal(set) static var rum = DDRUM(isNoOp: true) {
        // We must also set the Swift `Global.rum`
        // as it's used internally by auto-instrumentation feature.
        didSet { Global.rum = rum.sdkRUM }
    }
}

@available(*, deprecated, message: "Please use DDGlobal.tracer instead.")
@objcMembers
@objc(OTGlobal)
public class OTGlobal: NSObject {
    public static func initSharedTracer(_ tracer: OTTracer) {
        guard let ddtracer = tracer.dd else {
            return
        }
        sharedTracer = ddtracer
        Global.sharedTracer = ddtracer.swiftTracer
    }

    public internal(set) static var sharedTracer: OTTracer {
        get { DDGlobal.tracer }
        set { DDGlobal.tracer = newValue }
    }
}
