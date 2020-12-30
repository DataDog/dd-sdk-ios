/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
public class DDGlobal: NSObject {
    public static var sharedTracer: DatadogObjc.OTTracer = noopTracer {
        didSet {
            // We must also set the Swift `Global.tracer`
            // as it's used internally by auto-instrumentation feature.
            if let swiftTracer = sharedTracer.dd?.swiftTracer {
                Global.sharedTracer = swiftTracer
            }
        }
    }
    public static var rum: DatadogObjc.DDRUMMonitor = noopRUMMonitor {
        didSet {
            // We must also set the Swift `Global.rum`
            // as it's used internally by auto-instrumentation feature.
            if let swiftRUMMonitor = rum.swiftRUMMonitor {
                Global.rum = swiftRUMMonitor
            }
        }
    }
}
