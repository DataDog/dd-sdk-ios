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
    /// Whether or not receiving this command should start the "Background" view if no view is active
    /// and ``Datadog.Configuration.Builder.trackBackgroundEvents(_:)`` is enabled.
    var canStartBackgroundView: Bool { get }
    /// Whether or not receiving this command should start the "ApplicationLaunch" view if no view was yet started in current app process.
    var canStartApplicationLaunchView: Bool { get }
    /// Whether or not this command is considered a user intaraction
    var isUserInteraction: Bool { get }
}

// MARK: - RUM View related commands

internal struct RUMStartViewCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, it should start its own view, not the "Background"
    let canStartApplicationLaunchView = false // no, it should start its own view, not the "ApplicationLaunch"
    let isUserInteraction = true // a new View means there was a navigation, it's considered a User interaction

    /// The value holding stable identity of the RUM View.
    let identity: RUMViewIdentifiable

    /// The name of this View, rendered in RUM Explorer as `VIEW NAME`.
    let name: String

    /// The path of this View, rendered in RUM Explorer as `VIEW URL`.
    let path: String

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
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view
    let canStartApplicationLaunchView = false // no, we don't expect receiving it without an active view
    let isUserInteraction = false // a view can be stopped and in most cases should not be considered an interaction (if it's stopped because the user navigate inside the same app, the startView will happen shortly after this)

    /// The value holding stable identity of the RUM View.
    let identity: RUMViewIdentifiable
}

internal struct RUMAddCurrentViewErrorCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track errors in "Background" view
    let canStartApplicationLaunchView = true // yes, we want to track errors in "ApplicationLaunch" view
    let isUserInteraction = false // an error is not an interactive event

    /// The error message.
    let message: String
    /// Error type.
    let type: String?
    /// Error stacktrace.
    let stack: String?
    /// Whether this error crashed the host application
    let isCrash: Bool?
    /// The origin of this error.
    let source: RUMInternalErrorSource
    /// The platform type of the error (iOS, React Native, ...)
    let errorSourceType: RUMErrorEvent.Error.SourceType

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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes)
        self.isCrash = self.attributes.removeValue(forKey: CrossPlatformAttributes.errorIsCrash) as? Bool
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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes)
        self.isCrash = self.attributes.removeValue(forKey: CrossPlatformAttributes.errorIsCrash) as? Bool
    }
}

internal struct RUMAddViewTimingCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, it doesn't make sense to start "Background" view on receiving custom timing, as it will be `0ns` timing
    let canStartApplicationLaunchView = false // no, it doesn't make sense to start "ApplicationLaunch" view on receiving custom timing, as it will be `0ns` timing
    let isUserInteraction = false // a custom view timing is not an interactive event

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
    let canStartBackgroundView = true // yes, we want to track resources in "Background" view
    let canStartApplicationLaunchView = true // yes, we want to track resources in "ApplicationLaunch" view
    let isUserInteraction = false // a resource is not an interactive event

    /// Resource url
    let url: String
    /// HTTP method used to load the Resource
    let httpMethod: RUMMethod
    /// A type of the Resource if it's possible to determine on start (when the response MIME is not yet known).
    let kind: RUMResourceType?
    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    let spanContext: RUMSpanContext?
}

internal struct RUMAddResourceMetricsCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let canStartApplicationLaunchView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let isUserInteraction = false // an error is not an interactive event

    /// Resource metrics.
    let metrics: ResourceMetrics
}

internal struct RUMStopResourceCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let canStartApplicationLaunchView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let isUserInteraction = false // a resource is not an interactive event

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
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let canStartApplicationLaunchView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let isUserInteraction = false // a resource is not an interactive event

    /// The error message.
    let errorMessage: String
    /// Error type.
    let errorType: String?
    /// The origin of the error (network, webview, ...)
    let errorSource: RUMInternalErrorSource
    /// The platform type of the error (iOS, React Native, ...)
    let errorSourceType: RUMErrorEvent.Error.SourceType
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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes)
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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes)
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
    let canStartBackgroundView = true // yes, we want to track actions in "Background" view (e.g. it makes sense for custom actions)
    let canStartApplicationLaunchView = true // yes, we want to track actions in "ApplicationLaunch" view (e.g. it makes sense for custom actions)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMUserActionType
    let name: String
}

/// Stops continuous User Action.
internal struct RUMStopUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartUserActionCommand`)
    let canStartApplicationLaunchView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartUserActionCommand`)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMUserActionType
    let name: String?
}

/// Adds discrete (discontinuous) User Action.
internal struct RUMAddUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track actions in "Background" view (e.g. it makes sense for custom actions)
    let canStartApplicationLaunchView = true // yes, we want to track actions in "ApplicationLaunch" view (e.g. it makes sense for custom actions)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMUserActionType
    let name: String
}

// MARK: - RUM Long Task related commands

internal struct RUMAddLongTaskCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving long tasks in "Background" view
    let canStartApplicationLaunchView = true // yes, we want to track long tasks in "ApplicationLaunch" view (e.g. any hitches before presenting first UI)
    let isUserInteraction = false // a long task is not an interactive event

    let duration: TimeInterval
}

// MARK: - RUM Web Events related commands

/// RUM Events received from WebView should keep the active session alive, therefore they fire this command to do so. (ref: RUMM-1793)
internal struct RUMKeepSessionAliveCommand: RUMCommand {
    let canStartBackgroundView = false
    let canStartApplicationLaunchView = false
    let isUserInteraction = false
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
}
