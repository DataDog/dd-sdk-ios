/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
@objc(OTGlobal)
public class OTGlobal: NSObject {
    public static func initSharedTracer(_ tracer: OTTracer) {
        guard let ddtracer = tracer.dd else {
            return
        }

        sharedTracer = ddtracer

        // We must also set the Swift `sharedTracer` as it's used internally by auto-instrumentation feature.
        Global.sharedTracer = ddtracer.swiftTracer
    }

    public internal(set) static var sharedTracer: OTTracer = noopTracer
}
