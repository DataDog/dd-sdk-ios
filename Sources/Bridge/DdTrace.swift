/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2016-Present Datadog, Inc.
 */

import Foundation

/**
   The entry point to use Datadog's Trace feature.
 */
@objc(DdTrace)
public protocol DdTrace {

    /**
       Start a span, and returns a unique identifier for the span.
     */
    func startSpan(operation: NSString, timestamp: Int64, context: NSDictionary) -> NSString

    /**
       Finish a started span.
     */
    func finishSpan(spanId: NSString, timestamp: Int64, context: NSDictionary) -> Void

}
