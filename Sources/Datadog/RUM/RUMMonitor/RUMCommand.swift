/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Command processed through the tree of `RUMScopes`.
internal protocol RUMCommand {
    /// The time of command issue.
    var time: Date { set get }
    /// Attributes associated with the command.
    var attributes: [AttributeKey: AttributeValue] { set get }
}

// MARK: - RUM View related commands

internal struct RUMStartViewCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The value holding stable identity of the RUM View.
    let identity: RUMViewIdentifiable

    /// The name of this View, rendered in RUM Explorer as `VIEW NAME`.
    let name: String

    /// The path of this View, rendered in RUM Explorer as `VIEW URL`.
    let path: String

    /// Used to indicate if this command starts the very first View in the app.
    /// * default `false` means _it's not yet known_,
    /// * it can be set to `true` by the `RUMApplicationScope` which tracks this state.
    var isInitialView = false

    init(
        time: Date,
        identity: RUMViewIdentifiable,
        name: String?,
        path: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.attributes = attributes
        self.identity = identity
        self.name = name ?? identity.defaultViewPath
        self.path = path ?? identity.defaultViewPath
    }
}

internal struct RUMStopViewCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The value holding stable identity of the RUM View.
    let identity: RUMViewIdentifiable
}

internal struct RUMAddCurrentViewErrorCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let message: String
    /// Error type.
    let type: String?
    /// Error stacktrace.
    let stack: String?
    /// The origin of this error.
    let source: RUMInternalErrorSource

    init(
        time: Date,
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes
        self.message = message
        self.type = type
        self.stack = stack
    }

    init(
        time: Date,
        error: Error,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.time = time
        self.source = source
        self.attributes = attributes

        let dderror = DDError(error: error)
        self.message = dderror.message
        self.type = dderror.type
        self.stack = dderror.stack
    }
}

internal struct RUMAddViewTimingCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The name of the timing. It will be used as a JSON key, whereas the value will be the timing duration,
    /// measured since the start of the View.
    let timingName: String
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
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// Resource url
    let url: String
    /// HTTP method used to load the Resource
    let httpMethod: RUMMethod
    /// A type of the Resource if it's possible to determine on start (when the response MIME is not yet known).
    let kind: RUMResourceType?
    /// Whether or not the resource url targets a first party host, if that information is available.
    let isFirstPartyRequest: Bool?
    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    let spanContext: RUMSpanContext?
}

internal struct RUMAddResourceMetricsCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// Resource metrics.
    let metrics: ResourceMetrics
}

internal struct RUMStopResourceCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// A type of the Resource
    let kind: RUMResourceType
    /// HTTP status code of loading the Ressource
    let httpStatusCode: Int?
    /// The size of loaded Resource
    let size: Int64?
}

internal struct RUMStopResourceWithErrorCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    /// The error message.
    let errorMessage: String
    /// Error type.
    let errorType: String?
    /// The origin of the error (network, webview, ...)
    let errorSource: RUMInternalErrorSource
    /// Error stacktrace.
    let stack: String?
    /// HTTP status code of the Ressource error.
    let httpStatusCode: Int?

    init(
        resourceKey: String,
        time: Date,
        message: String,
        type: String?,
        source: RUMInternalErrorSource,
        httpStatusCode: Int?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.resourceKey = resourceKey
        self.time = time
        self.errorMessage = message
        self.errorType = type
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
        source: RUMInternalErrorSource,
        httpStatusCode: Int?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.resourceKey = resourceKey
        self.time = time
        self.errorSource = source
        self.attributes = attributes
        self.httpStatusCode = httpStatusCode

        let dderror = DDError(error: error)
        self.errorMessage = dderror.message
        self.errorType = dderror.type
        // The stack will give the networking error (`NSError`) description in most cases:
        self.stack = dderror.stack
    }
}

// MARK: - RUM User Action related commands

internal protocol RUMUserActionCommand: RUMCommand {
    /// The action identifying the RUM User Action.
    var actionType: RUMUserActionType { get }
}

/// Starts continuous User Action.
internal struct RUMStartUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String
}

/// Stops continuous User Action.
internal struct RUMStopUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String?
}

/// Adds discrete (discontinuous) User Action.
internal struct RUMAddUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    let actionType: RUMUserActionType
    let name: String
}

// MARK: - RUM Long Task related commands

internal struct RUMAddLongTaskCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]

    let duration: TimeInterval
}
