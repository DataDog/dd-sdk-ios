/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Command processed through the tree of `RUMScopes`.
internal protocol RUMCommand {
    /// The time of command issue.
    var time: Date { get }
    /// Attributes associated with the command.
    var attributes: [AttributeKey: AttributeValue] { get }
}

// MARK: - RUM View related commands

internal struct RUMStartViewCommand: RUMCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// The object (typically `UIViewController`) identifying the RUM View.
    let identity: AnyObject

    /// Used to indicate if this command starts the very first View in the app.
    /// * default `false` means _it's not yet known_,
    /// * it can be set to `true` by the `RUMApplicationScope` which tracks this state.
    var isInitialView = false
}

internal struct RUMStopViewCommand: RUMCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// The object (typically `UIViewController`) identifying the RUM View.
    let identity: AnyObject
}

internal struct RUMAddCurrentViewErrorCommand: RUMCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let message: String
    /// The origin of this error.
    let source: RUMErrorSource
    /// Error stacktrace.
    let stack: String?

    init(
        time: Date,
        message: String,
        source: RUMErrorSource,
        stack: (file: StaticString, line: UInt)?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes
        self.message = message
        self.stack = stack.flatMap { "\($0.file): \($0.line)" }
    }

    init(
        time: Date,
        source: RUMErrorSource,
        error: Error,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes

        let dderror = DDError(error: error)
        self.message = dderror.message
        self.stack = dderror.details
    }
}

// MARK: - RUM Resource related commands

internal protocol RUMResourceCommand: RUMCommand {
    /// The name identifying the RUM Resource.
    var resourceName: String { get }
}

internal struct RUMStartResourceCommand: RUMResourceCommand {
    let resourceName: String
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// Resource url
    let url: String
    /// HTTP method used to load the Resource
    let httpMethod: String
}

internal struct RUMStopResourceCommand: RUMResourceCommand {
    let resourceName: String
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// A type of the Resource (image, font, ...)
    let type: String
    /// HTTP status code of loading the Ressource
    let httpStatusCode: Int?
    /// The size of loaded Resource
    let size: UInt64?
}

internal struct RUMStopResourceWithErrorCommand: RUMResourceCommand {
    let resourceName: String
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let errorMessage: String
    /// The origin of the error (network, webview, ...)
    let errorSource: RUMErrorSource
    /// HTTP status code of the Ressource error.
    let httpStatusCode: Int?
}

// MARK: - RUM User Action related commands

internal protocol RUMUserActionCommand: RUMCommand {
    /// The action identifying the RUM User Action.
    var actionType: RUMUserActionType { get }
}

/// Starts continuous User Action.
internal struct RUMStartUserActionCommand: RUMUserActionCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
}

/// Stops continuous User Action.
internal struct RUMStopUserActionCommand: RUMUserActionCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
}

/// Adds discrete (discontinuous) User Action.
internal struct RUMAddUserActionCommand: RUMUserActionCommand {
    let time: Date
    let attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
}
