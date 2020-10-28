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
    var attributes: [AttributeKey: AttributeValue] { set get }
}

// MARK: - RUM View related commands

internal struct RUMStartViewCommand: RUMCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The object (typically `UIViewController`) identifying the RUM View.
    let identity: AnyObject

    /// The path of this View, rendered in RUM Explorer.
    let path: String

    /// Used to indicate if this command starts the very first View in the app.
    /// * default `false` means _it's not yet known_,
    /// * it can be set to `true` by the `RUMApplicationScope` which tracks this state.
    var isInitialView = false

    init(time: Date, identity: AnyObject, path: String?, attributes: [AttributeKey: AttributeValue]) {
        self.time = time
        self.attributes = attributes
        self.identity = identity
        self.path = path ?? RUMStartViewCommand.viewPath(from: identity)
    }

    private static func viewPath(from id: AnyObject) -> String {
        return "\(type(of: id))"
    }
}

internal struct RUMStopViewCommand: RUMCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The object (typically `UIViewController`) identifying the RUM View.
    let identity: AnyObject
}

internal struct RUMAddCurrentViewErrorCommand: RUMCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let message: String
    /// The origin of this error.
    let source: RUMDataSource
    /// Error stacktrace.
    let stack: String?

    init(
        time: Date,
        message: String,
        stack: String?,
        source: RUMDataSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes
        self.message = message
        self.stack = stack
    }

    init(
        time: Date,
        error: Error,
        source: RUMDataSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes

        let dderror = DDError(error: error)
        self.message = dderror.title
        self.stack = dderror.details
    }
}

// MARK: - RUM Resource related commands

internal protocol RUMResourceCommand: RUMCommand {
    /// The key identifying the RUM Resource.
    var resourceKey: String { get }
}

/// Tracing information propagated by Tracing to the underlying `URLRequest`. It is passed to the RUM backend
/// in order to create the APM span. The actual `Span` is not send by the SDK.
internal struct RUMSpanContext {
    let traceID: String
    let spanID: String
}

internal struct RUMStartResourceCommand: RUMResourceCommand {
    let resourceKey: String
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// Resource url
    let url: String
    /// HTTP method used to load the Resource
    let httpMethod: RUMHTTPMethod
    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    let spanContext: RUMSpanContext?
}

internal struct RUMAddResourceMetricsCommand: RUMResourceCommand {
    let resourceKey: String
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// Resource metrics.
    let metrics: ResourceMetrics
}

internal struct RUMStopResourceCommand: RUMResourceCommand {
    let resourceKey: String
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// A type of the Resource
    let kind: RUMResourceKind
    /// HTTP status code of loading the Ressource
    let httpStatusCode: Int?
    /// The size of loaded Resource
    let size: Int64?
}

internal struct RUMStopResourceWithErrorCommand: RUMResourceCommand {
    let resourceKey: String
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let errorMessage: String
    /// The origin of the error (network, webview, ...)
    let errorSource: RUMErrorSource
    /// Error stacktrace.
    let stack: String?
    /// HTTP status code of the Ressource error.
    let httpStatusCode: Int?

    init(
        resourceKey: String,
        time: Date,
        message: String,
        source: RUMErrorSource,
        httpStatusCode: Int?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.resourceKey = resourceKey
        self.time = time
        self.errorMessage = message
        self.errorSource = source
        self.attributes = attributes
        self.httpStatusCode = httpStatusCode
        // The stack will be meaningless in most cases as it will go down to the networking code:
        self.stack = nil
    }

    init(
        resourceKey: String,
        time: Date,
        error: Error,
        source: RUMErrorSource,
        httpStatusCode: Int?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.resourceKey = resourceKey
        self.time = time
        self.errorSource = source
        self.attributes = attributes
        self.httpStatusCode = httpStatusCode

        let dderror = DDError(error: error)
        self.errorMessage = dderror.title
        // The stack will give the networking error (`NSError`) description in most cases:
        self.stack = dderror.details
    }
}

// MARK: - RUM User Action related commands

internal protocol RUMUserActionCommand: RUMCommand {
    /// The action identifying the RUM User Action.
    var actionType: RUMUserActionType { get }
}

/// Starts continuous User Action.
internal struct RUMStartUserActionCommand: RUMUserActionCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String
}

/// Stops continuous User Action.
internal struct RUMStopUserActionCommand: RUMUserActionCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String?
}

/// Adds discrete (discontinuous) User Action.
internal struct RUMAddUserActionCommand: RUMUserActionCommand {
    let time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String
}
