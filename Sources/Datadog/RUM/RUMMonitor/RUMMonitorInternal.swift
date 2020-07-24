/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum RUMUserActionType {
    case tap
    case scroll
    case swipe
    case custom
}

/// TODO: RUMM-585 - what else parameters do we need in each method?
internal protocol RUMMonitorInternal {
    func start(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    func stop(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    func addViewError(message: String, error: Error?, attributes: [AttributeKey: AttributeValue]?)

    func start(resource resourceName: String, url: String, httpMethod: String, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, type: String, httpStatusCode: Int?, size: UInt64?, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, withError errorMessage: String, errorSource: String, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]?)

    func start(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
    func stop(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
    func add(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
}
