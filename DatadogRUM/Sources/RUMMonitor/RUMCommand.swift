/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Command processed through the tree of `RUMScopes`.
internal protocol RUMCommand {
    /// The time of command issue.
    var time: Date { set get }
    /// Attributes associated with the command.
    var attributes: [AttributeKey: AttributeValue] { set get }
    /// Whether or not receiving this command should start the "Background" view if no view is active
    /// and ``RUM.Configuration.trackBackgroundEvents`` is enabled.
    var canStartBackgroundView: Bool { get }
    /// Whether or not this command is considered a user intaraction
    var isUserInteraction: Bool { get }
    /// A type of event missed upon receiving this command in case of absence of an active view; `nil` if none or N/A.
    var missedEventType: SessionEndedMetric.MissedEventType? { get }
}

internal struct RUMSDKInitCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue] = [:]
    var canStartBackgroundView = false
    var isUserInteraction = false
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

internal struct RUMApplicationStartCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    var canStartBackgroundView = false
    var isUserInteraction = false
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

internal struct RUMStopSessionCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue] = [:]
    let canStartBackgroundView = false // no, stopping a session should not start a backgorund session
    let isUserInteraction = false
    let missedEventType: SessionEndedMetric.MissedEventType? = nil

    init(time: Date) {
        self.time = time
    }
}

// MARK: - RUM View related commands

internal struct RUMStartViewCommand: RUMCommand, RUMViewScopePropagatableAttributes {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, it should start its own view, not the "Background"
    let isUserInteraction = true // a new View means there was a navigation, it's considered a User interaction

    /// The value holding stable identity of the RUM View.
    let identity: ViewIdentifier

    /// The name of this View, rendered in RUM Explorer as `VIEW NAME`.
    let name: String

    /// The path of this View, rendered in RUM Explorer as `VIEW URL`.
    let path: String

    /// The type of instrumentation that started this view.
    let instrumentationType: SessionEndedMetric.ViewInstrumentationType
    let missedEventType: SessionEndedMetric.MissedEventType? = nil

    init(
        time: Date,
        identity: ViewIdentifier,
        name: String,
        path: String,
        attributes: [AttributeKey: AttributeValue],
        instrumentationType: SessionEndedMetric.ViewInstrumentationType
    ) {
        self.time = time
        self.attributes = attributes
        self.identity = identity
        self.name = name
        self.path = path
        self.instrumentationType = instrumentationType
    }
}

internal struct RUMStopViewCommand: RUMCommand, RUMViewScopePropagatableAttributes {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view
    let isUserInteraction = false // a view can be stopped and in most cases should not be considered an interaction (if it's stopped because the user navigate inside the same app, the startView will happen shortly after this)

    /// The value holding stable identity of the RUM View.
    let identity: ViewIdentifier
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

/// Any error command, like exception or App Hang.
internal protocol RUMErrorCommand: RUMCommand {
    /// The error message.
    var message: String { get }
    /// Error type.
    var type: String? { get }
    /// Error stacktrace.
    var stack: String? { get }
    /// Mobile-specific category of the error to empower high-level grouping of different types of errors.
    var category: RUMErrorCategory { get }
    /// Whether this error has crashed the host application
    var isCrash: Bool? { get }
    /// The origin of this error.
    var source: RUMInternalErrorSource { get }
    /// The platform type of the error (iOS, React Native, ...)
    var errorSourceType: RUMErrorEvent.Error.SourceType { get }
    /// An information about the threads currently running in the process.
    var threads: [DDThread]? { get }
    /// The list of binary images referenced from `stack` and `threads`.
    var binaryImages: [BinaryImage]? { get }
    /// Indicates whether any stack trace information in `stack` or `threads` was truncated due to stack trace minimization.
    var isStackTraceTruncated: Bool? { get }
}

/// Adds exception error to current view.
///
/// Using this command results with classifying the error as "Exception" in Datadog app (`@error.category: Exception`).
internal struct RUMAddCurrentViewErrorCommand: RUMErrorCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track errors in "Background" view
    let isUserInteraction = false // an error is not an interactive event

    let message: String
    let type: String?
    let stack: String?
    let category: RUMErrorCategory = .exception
    let isCrash: Bool?
    let source: RUMInternalErrorSource
    let errorSourceType: RUMErrorEvent.Error.SourceType
    let threads: [DDThread]?
    let binaryImages: [BinaryImage]?
    let isStackTraceTruncated: Bool?
    let missedEventType: SessionEndedMetric.MissedEventType? = .error

    /// Constructor dedicated to errors defined by message, type and stack.
    init(
        time: Date,
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.init(
            time: time,
            message: message,
            type: type,
            stack: stack,
            source: source,
            isCrash: nil,
            threads: nil,
            binaryImages: nil,
            isStackTraceTruncated: nil,
            attributes: attributes
        )
    }

    /// Constructor dedicated to errors defined by `Error` object.
    init(
        time: Date,
        error: Error,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        let dderror = DDError(error: error)
        self.init(
            time: time,
            message: dderror.message,
            type: dderror.type,
            stack: dderror.stack,
            source: source,
            isCrash: nil,
            threads: nil,
            binaryImages: nil,
            isStackTraceTruncated: nil,
            attributes: attributes
        )
    }

    /// Broad constructor for all kinds of errors.
    init(
        time: Date,
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        isCrash: Bool?,
        threads: [DDThread]?,
        binaryImages: [BinaryImage]?,
        isStackTraceTruncated: Bool?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        var attributes = attributes
        let isCrossPlatformCrash: Bool? = attributes.removeValue(forKey: CrossPlatformAttributes.errorIsCrash)?.dd.decode()
        let crossPlatformSourceType = RUMErrorSourceType.extract(from: &attributes)

        self.time = time
        self.attributes = attributes
        self.message = message
        self.type = type
        self.stack = stack
        self.isCrash = isCrossPlatformCrash ?? isCrash
        self.source = source
        self.errorSourceType = crossPlatformSourceType ?? .ios
        self.threads = threads
        self.binaryImages = binaryImages
        self.isStackTraceTruncated = isStackTraceTruncated
    }
}

/// Adds App Hang error to current view.
///
/// Using this command results with classifying the error as "App Hang" in Datadog app (`@error.category: App Hang`).
internal struct RUMAddCurrentViewAppHangCommand: RUMErrorCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't want to track App Hangs in "Background" view
    let isUserInteraction = false // an error is not an interactive event

    let message: String
    let type: String?
    let stack: String?
    let category: RUMErrorCategory = .appHang
    let isCrash: Bool? = false
    let source: RUMInternalErrorSource = .source
    let errorSourceType: RUMErrorEvent.Error.SourceType = .ios
    let threads: [DDThread]?
    let binaryImages: [BinaryImage]?
    let isStackTraceTruncated: Bool?

    /// The duration of hang.
    let hangDuration: TimeInterval
    let missedEventType: SessionEndedMetric.MissedEventType? = .error
}

internal struct RUMAddCurrentViewMemoryWarningCommand: RUMErrorCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false
    let isUserInteraction = false

    let message: String
    let type: String?
    let stack: String?
    let category: RUMErrorCategory = .memoryWarning
    let isCrash: Bool? = false
    let source: RUMInternalErrorSource = .source
    let errorSourceType: RUMErrorEvent.Error.SourceType = .ios
    let threads: [DDThread]?
    let binaryImages: [BinaryImage]?
    let isStackTraceTruncated: Bool?

    let missedEventType: SessionEndedMetric.MissedEventType? = .error
}

internal struct RUMAddViewLoadingTime: RUMCommand, RUMViewScopePropagatableAttributes {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, it doesn't make sense to start "Background" view on receiving custom timing, as it will be `0ns` timing
    let isUserInteraction = false // a custom view timing is not an interactive event

    /// The name of the timing. It will be used as a JSON key, whereas the value will be the timing duration,
    /// measured since the start of the View.
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

internal struct RUMAddViewTimingCommand: RUMCommand, RUMViewScopePropagatableAttributes {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, it doesn't make sense to start "Background" view on receiving custom timing, as it will be `0ns` timing
    let isUserInteraction = false // a custom view timing is not an interactive event

    /// The name of the timing. It will be used as a JSON key, whereas the value will be the timing duration,
    /// measured since the start of the View.
    let timingName: String
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

// MARK: - RUM Resource related commands

internal protocol RUMResourceCommand: RUMCommand {
    /// The key identifying the RUM Resource.
    var resourceKey: String { get }
}

/// Tracing information propagated by Tracing to the underlying `URLRequest`. It is passed to the RUM backend
/// in order to create the APM span. The actual `Span` is not send by the SDK.
internal struct RUMSpanContext {
    /// The trace ID injected to `URLRequest` that issues RUM resource.
    let traceID: TraceID
    /// The span ID injected to `URLRequest` that issues RUM resource.
    let spanID: SpanID
    /// The sampling rate applied to the trace (a value between `0.0` and `1.0`).
    let samplingRate: Double
}

internal struct RUMStartResourceCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track resources in "Background" view
    let isUserInteraction = false // a resource is not an interactive event

    /// Resource url
    let url: String
    /// HTTP method used to load the Resource
    let httpMethod: RUMMethod
    /// A type of the Resource if it's possible to determine on start (when the response MIME is not yet known).
    let kind: RUMResourceType?
    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    let spanContext: RUMSpanContext?
    let missedEventType: SessionEndedMetric.MissedEventType? = .resource
}

internal struct RUMAddResourceMetricsCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let isUserInteraction = false // an error is not an interactive event

    /// Resource metrics.
    let metrics: ResourceMetrics
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

internal struct RUMStopResourceCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
    let isUserInteraction = false // a resource is not an interactive event

    /// A type of the Resource
    let kind: RUMResourceType
    /// HTTP status code of loading the Ressource
    let httpStatusCode: Int?
    /// The size of loaded Resource
    let size: Int64?
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

internal struct RUMStopResourceWithErrorCommand: RUMResourceCommand {
    let resourceKey: String
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartResourceCommand`)
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
    let missedEventType: SessionEndedMetric.MissedEventType? = .error

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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes) ?? .ios
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

        self.errorSourceType = RUMErrorSourceType.extract(from: &self.attributes) ?? .ios
    }
}

// MARK: - RUM User Action related commands

internal protocol RUMUserActionCommand: RUMCommand {
    /// The action identifying the RUM User Action.
    var actionType: RUMActionType { get }
}

/// Starts continuous User Action.
internal struct RUMStartUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track actions in "Background" view (e.g. it makes sense for custom actions)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMActionType
    let name: String
    let missedEventType: SessionEndedMetric.MissedEventType? = .action
}

/// Stops continuous User Action.
internal struct RUMStopUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving it without an active view (started earlier on `RUMStartUserActionCommand`)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMActionType
    let name: String?
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

/// Adds discrete (discontinuous) User Action.
internal struct RUMAddUserActionCommand: RUMUserActionCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we want to track actions in "Background" view (e.g. it makes sense for custom actions)
    let isUserInteraction = true // a user action definitely is a User Interacgion

    let actionType: RUMActionType
    let name: String
    let missedEventType: SessionEndedMetric.MissedEventType? = .action
}

/// Adds that a feature flag has been evaluated to the view
internal struct RUMAddFeatureFlagEvaluationCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = true // yes, we don't want to miss evaluation of flags that may affect background tasks
    let isUserInteraction = false
    let name: String
    let value: Encodable
    let missedEventType: SessionEndedMetric.MissedEventType? = nil

    init(time: Date, name: String, value: Encodable) {
        self.time = time
        self.attributes = [:]
        self.name = name
        self.value = value
    }
}

// MARK: - RUM Long Task related commands

internal struct RUMAddLongTaskCommand: RUMCommand {
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let canStartBackgroundView = false // no, we don't expect receiving long tasks in "Background" view
    let isUserInteraction = false // a long task is not an interactive event

    let duration: TimeInterval
    let missedEventType: SessionEndedMetric.MissedEventType? = .longTask
}

// MARK: - RUM Web Events related commands

/// RUM Events received from WebView should keep the active session alive, therefore they fire this command to do so. (ref: RUMM-1793)
internal struct RUMKeepSessionAliveCommand: RUMCommand {
    let canStartBackgroundView = false
    let isUserInteraction = false
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}

// MARK: - Cross-platform perf metrics

internal struct RUMUpdatePerformanceMetric: RUMCommand {
    let canStartBackgroundView = false
    let isUserInteraction = false
    let metric: PerformanceMetric
    let value: Double
    var time: Date
    var attributes: [AttributeKey: AttributeValue]
    let missedEventType: SessionEndedMetric.MissedEventType? = nil
}
