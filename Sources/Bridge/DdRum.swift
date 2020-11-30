/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2016-Present Datadog, Inc.
 */

import Foundation

/**
   The entry point to use Datadog's RUM feature.
 */
@objc(DdRum)
public protocol DdRum {

    /**
       Start tracking a RUM View.
     */
    func startView(key: NSString, name: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Stop tracking a RUM View.
     */
    func stopView(key: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Start tracking a RUM Action.
     */
    func startAction(type: NSString, name: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Stop tracking the ongoing RUM Action.
     */
    func stopAction(timestamp: Int64, context: NSDictionary) -> Void

    /**
       Add a RUM Action.
     */
    func addAction(type: NSString, name: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Start tracking a RUM Resource.
     */
    func startResource(key: NSString, method: NSString, url: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Stop tracking a RUM Resource.
     */
    func stopResource(key: NSString, statusCode: Int64, kind: NSString, timestamp: Int64, context: NSDictionary) -> Void

    /**
       Add a RUM Error.
     */
    func addError(message: NSString, source: NSString, stacktrace: NSString, timestamp: Int64, context: NSDictionary) -> Void

}
