/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
@objc(DDGlobal)
public class DDGlobal: NSObject {
    public internal(set) static var sharedTracer: OTTracer = noopTracer {
        didSet {
            // We must also set the Swift `Global.tracer`
            // as it's used internally by auto-instrumentation feature.
            if let ddTracer = sharedTracer.dd?.swiftTracer {
                Global.sharedTracer = ddTracer
            }
        }
    }
    public internal(set) static var rum = DDRUM(Global.rum) {
        // We must also set the Swift `Global.rum`
        // as it's used internally by auto-instrumentation feature.
        didSet { Global.rum = rum.sdkRUM }
    }
}
