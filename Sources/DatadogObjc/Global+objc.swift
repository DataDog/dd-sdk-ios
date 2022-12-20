/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import struct Datadog.Global

@objc
public class DDGlobal: NSObject {
    @objc public static var sharedTracer = DatadogObjc.DDTracer(swiftTracer: Datadog.Global.sharedTracer) {
        didSet {
            // We must also set the Swift `Global.tracer`
            // as it's used internally by auto-instrumentation feature.
            Datadog.Global.sharedTracer = sharedTracer.swiftTracer
        }
    }

    @objc public static var rum = DatadogObjc.DDRUMMonitor(swiftRUMMonitor: Datadog.Global.rum) {
        didSet {
            // We must also set the Swift `Global.rum`
            // as it's used internally by auto-instrumentation feature.
            Datadog.Global.rum = rum.swiftRUMMonitor
        }
    }
}
