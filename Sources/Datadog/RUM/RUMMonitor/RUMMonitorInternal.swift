/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// TODO: RUMM-585 - what else parameters do we need in each method?
internal protocol RUMMonitorInternal {
    func start(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    func stop(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    func add(viewErrorMessage: String, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?, stack: (file: StaticString, line: UInt)?)
    func add(viewError: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?)

    func start(resource resourceName: String, url: URL, method: RUMHTTPMethod, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, kind: RUMResourceKind, httpStatusCode: Int?, size: UInt64?, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, withErrorMessage errorMessage: String, errorSource: RUMErrorSource, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]?)
    func stop(resource resourceName: String, withError error: Error, errorSource: RUMErrorSource, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]?)

    func start(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
    func stop(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
    func add(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?)
}
