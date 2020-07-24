/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Commands processed by the tree of `RUMScopes`.
internal enum RUMCommand {
    // MARK: - Commands Published by `RUMMonitor`

    case startView(id: AnyObject, attributes: [AttributeKey: AttributeValue], time: Date)
    case stopView(id: AnyObject, attributes: [AttributeKey: AttributeValue], time: Date)
    case addCurrentViewError(message: String, error: Error?, attributes: [AttributeKey: AttributeValue], time: Date)

    case startResource(resourceName: String, attributes: [AttributeKey: AttributeValue], time: Date)
    case stopResource(resourceName: String, attributes: [AttributeKey: AttributeValue], time: Date)
    case stopResourceWithError(resourceName: String, error: Error, attributes: [AttributeKey: AttributeValue], time: Date)

    case startUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue], time: Date)
    case stopUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue], time: Date)
    case addUserAction(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue], time: Date)

    // MARK: - Commands Published by `RUMScopes`

    /// Replaces `.startView` command for the first View started in the application.
    case startInitialView(id: AnyObject, attributes: [AttributeKey: AttributeValue], time: Date)

    // MARK: - Properties

    /// Time of the command issue.
    var time: Date {
        switch self {
        case .startView(_, _, let time),
             .stopView(_, _, let time),
             .addCurrentViewError(_, _, _, let time),
             .startResource(_, _, let time),
             .stopResource(_, _, let time),
             .stopResourceWithError(_, _, _, let time),
             .startUserAction(_, _, let time),
             .stopUserAction(_, _, let time),
             .addUserAction(_, _, let time),
             .startInitialView(_, _, let time):
            return time
        }
    }

    /// Attributes associated with the command.
    var attributes: [AttributeKey: AttributeValue] {
        switch self {
        case .startView(_, let attributes, _),
             .stopView(_, let attributes, _),
             .addCurrentViewError(_, _, let attributes, _),
             .startResource(_, let attributes, _),
             .stopResource(_, let attributes, _),
             .stopResourceWithError(_, _, let attributes, _),
             .startUserAction(_, let attributes, _),
             .stopUserAction(_, let attributes, _),
             .addUserAction(_, let attributes, _),
             .startInitialView(_, let attributes, _):
            return attributes
        }
    }
}
