/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum RUMUserAction {
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

    func start(resource resourceName: String, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, withError error: Error, attributes: [AttributeKey: AttributeValue]?)

    func start(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
    func stop(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
    func add(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
}
