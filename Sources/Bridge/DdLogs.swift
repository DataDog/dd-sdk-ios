/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2016-Present Datadog, Inc.
 */

import Foundation

/**
   The entry point to use Datadog's Logs feature.
 */
@objc(DdLogs)
public protocol DdLogs {

    /**
       Send a log with level debug.
     */
    func debug(message: NSString, context: NSDictionary) -> Void

    /**
       Send a log with level info.
     */
    func info(message: NSString, context: NSDictionary) -> Void

    /**
       Send a log with level warn.
     */
    func warn(message: NSString, context: NSDictionary) -> Void

    /**
       Send a log with level error.
     */
    func error(message: NSString, context: NSDictionary) -> Void

}
