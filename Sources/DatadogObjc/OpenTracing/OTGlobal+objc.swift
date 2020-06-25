/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

@objcMembers
@objc(OTGlobal)
public class DDOTGlobal: NSObject {
    public static func initSharedTracer(_ tracer: DDOTTracer) {
        // Corresponds to:
        // + (void)initSharedTracer:(id<OTTracer>)tracer;
        sharedTracer = tracer

        // We must also set the Swift `sharedTracer` as it's used internally by auto-instrumentation feature.
        Global.sharedTracer = tracer.swiftTracer
    }

    // Corresponds to:
    // + (id<OTTracer>)sharedTracer
    public internal(set) static var sharedTracer: DDOTTracer?
}
