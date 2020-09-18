/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

/// Namespace storing global Datadog components.
public struct Global {
    /// Shared tracer instance to use throughout the app.
    public static var sharedTracer: OTTracer = DDNoopGlobals.tracer {
        didSet {
            #if canImport(_Datadog_TestRunner)
            if DDTestRunner.instance != nil, !(oldValue is DDNoopTracer) {
                sharedTracer = oldValue
            }
            #endif
        }
    }

    /// Shared RUM monitor instance to use throughout the app.
    public static var rum: DDRUMMonitor = DDNoopRUMMonitor()
}
