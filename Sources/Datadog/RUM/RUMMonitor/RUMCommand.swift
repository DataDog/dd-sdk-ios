/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Commands processed by the tree of `RUMScopes`.
internal enum RUMCommand {
    case startView(id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    case stopView(id: AnyObject, attributes: [AttributeKey: AttributeValue]?)
    case addCurrentViewError(message: String, error: Error?, attributes: [AttributeKey: AttributeValue]?)

    case startResource(resourceName: String, attributes: [AttributeKey: AttributeValue]?)
    case stopResource(resourceName: String, attributes: [AttributeKey: AttributeValue]?)
    case stopResourceWithError(resourceName: String, error: Error, attributes: [AttributeKey: AttributeValue]?)

    case startUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
    case stopUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
    case addUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?)
}
