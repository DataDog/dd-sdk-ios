/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

// swiftlint:disable function_default_parameter_at_end

#if os(iOS)
/// Selects the RUM view used to attribute explicitly targeted telemetry.
///
/// This API is experimental and may change before becoming generally available.
/// It does not expose or retain an internal RUM view identifier.
@_spi(Experimental)
@available(iOS 27.0, *)
public struct RUMViewTarget {
    fileprivate let sceneIdentifier: RUMSceneIdentifier

    private init(sceneIdentifier: RUMSceneIdentifier) {
        self.sceneIdentifier = sceneIdentifier
    }

    /// Targets the current tracked RUM view in `scene` when telemetry is
    /// processed.
    @MainActor
    public static func current(in scene: UIWindowScene) -> Self {
        Self(
            sceneIdentifier: RUMSceneIdentifier(
                rawValue: scene.session.persistentIdentifier
            )
        )
    }
}

/// Compatibility spelling retained while the experimental API is under review.
@_spi(Experimental)
@available(iOS 27.0, *)
public typealias RUMOperationViewTarget = RUMViewTarget
#endif

/// Convenience extension for defining `RUMMonitorProtocol` methods with default parameter values.
///
/// ⚠️ Be extra cautious when adding new methods here. Each method overloads (shadows) its original
/// definition in extended protocol, which makes the Swift compiler no longer require it on the type conforming
/// to `RUMMonitorProtocol`. If that conformance is not provided, it will cause an infinite recursive call and crash.
///
/// TODO: RUMM-3347 Use code generation for supplying default parameter values in public protocols
public extension RUMMonitorProtocol {
    // MARK: - views

    #if !os(watchOS)
    /// Starts RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - name: the name of the view. If not provided, the `viewController` class name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(viewController: viewController, name: name, attributes: attributes)
    }

    /// Stops RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(viewController: viewController, attributes: attributes)
    }
    #endif

    /// Starts RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed later to `stopView(key:attributes:)`.
    ///   - name: the name of the view. If not provided, the `key` name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        key: String,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(key: key, name: name, attributes: attributes)
    }

    /// Stops RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed earlier to `startView(key:name:attributes:)`.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(key: key, attributes: attributes)
    }

    #if os(iOS)
    /// Starts a RUM view in a specific window scene.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// Pair this call with `stopView(key:in:attributes:)` using the same key and scene.
    /// - Parameters:
    ///   - key: a `String` value identifying this view within `scene`.
    ///   - name: the name of the view. If not provided, the `key` name will be used.
    ///   - scene: the window scene that owns this view.
    ///   - attributes: custom attributes to attach to this view.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startView(
        key: String,
        name: String? = nil,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMSceneTargetedManualViewBridge.startView(
            on: self,
            key: key,
            name: name,
            attributes: attributes,
            sceneIdentifier: RUMSceneIdentifier(
                rawValue: scene.session.persistentIdentifier
            )
        )
    }

    /// Stops a RUM view in a specific window scene.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// It only pairs with `startView(key:name:in:attributes:)` made for the same
    /// key and scene.
    /// - Parameters:
    ///   - key: a `String` value identifying the view within `scene`.
    ///   - scene: the window scene that owns this view.
    ///   - attributes: custom attributes to attach to this view.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func stopView(
        key: String,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMSceneTargetedManualViewBridge.stopView(
            on: self,
            key: key,
            attributes: attributes,
            sceneIdentifier: RUMSceneIdentifier(
                rawValue: scene.session.persistentIdentifier
            )
        )
    }
    #endif

    // MARK: - errors

    /// Adds RUM error to current RUM view.
    /// - Parameters:
    ///   - message: error message.
    ///   - type: the type of the error.
    ///   - stack: stack trace of the error. No specific format is required. If not specified, it will be inferred from `file` and `line`.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    ///   - file: the file in which the error occurred (the default is the `#fileID` of the caller).
    ///   - line: the line number on which the error occurred (the default is the `#line` of the caller).
    func addError(
        message: String,
        type: String? = nil,
        stack: String? = nil,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #fileID,
        line: UInt? = #line
    ) {
        addError(
            message: message,
            type: type,
            stack: stack,
            source: source,
            attributes: attributes,
            file: file,
            line: line
        )
    }

    /// Adds RUM error to current RUM view.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to infer error details.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addError(error: error, source: source, attributes: attributes)
    }

    #if os(iOS)
    /// Adds an error to the selected scene's current tracked view.
    ///
    /// This API is experimental. A scene without a live view falls back to the
    /// independently inferred view or process representative. Reporting an error
    /// does not change that representative. File and line supply a missing stack.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func addError(
        message: String,
        type: String? = nil,
        stack: String? = nil,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #fileID,
        line: UInt? = #line
    ) {
        RUMErrorViewTargetBridge.addError(
            on: self,
            message: message,
            type: type,
            stack: stack,
            source: source,
            attributes: attributes,
            file: file,
            line: line,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Adds an Error to the selected scene's current tracked view.
    ///
    /// This experimental overload uses independent inference when the scene has
    /// no live view. Resource errors retain the owner captured by startResource.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMErrorViewTargetBridge.addError(
            on: self, error: error, source: source, attributes: attributes, explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Adds an Error to the selected current view and completes after processing.
    ///
    /// This API is experimental. The callback also runs when the SDK drops the
    /// error; it does not indicate backend delivery. Custom monitors retain their
    /// existing completion-handler behavior.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        completionHandler: @escaping CompletionHandler
    ) {
        RUMErrorViewTargetBridge.addError(
            on: self,
            error: error,
            source: source,
            attributes: attributes,
            completionHandler: completionHandler,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    // MARK: - resources

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - request: the `URLRequest` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, request: request, attributes: attributes)
    }

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - url: the `URL` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, url: url, attributes: attributes)
    }

    /// Starts RUM resource
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently loaded.
    ///   - httpMethod: HTTP method of this resource
    ///   - urlString: the url string of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes)
    }

    #if os(iOS)
    /// Starts a Resource on the selected scene's current tracked view.
    ///
    /// This API is experimental. If the selected scene has no live view, existing
    /// inferred and process-representative fallbacks apply. The Resource key must
    /// be unique among all Resources being tracked. Metrics and completion keep
    /// the start owner even after navigation; they do not need another target.
    /// The request supplies the URL, method and inferred Resource type.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        request: URLRequest,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMResourceViewTargetBridge.startResource(
            on: self,
            resourceKey: resourceKey,
            request: request,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Starts a Resource on the selected scene's current tracked view.
    ///
    /// This API is experimental. If the selected scene has no live view, existing
    /// inferred and process-representative fallbacks apply. The Resource key must
    /// be unique among all Resources being tracked. Metrics and completion keep
    /// the start owner even after navigation; they do not need another target.
    /// The URL form uses the GET method.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        url: URL,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMResourceViewTargetBridge.startResource(
            on: self,
            resourceKey: resourceKey,
            url: url,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Starts a Resource on the selected scene's current tracked view.
    ///
    /// This API is experimental. If the selected scene has no live view, existing
    /// inferred and process-representative fallbacks apply. The Resource key must
    /// be unique among all Resources being tracked. Metrics and completion keep
    /// the start owner even after navigation; they do not need another target.
    /// The supplied method and URL string are preserved.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMResourceViewTargetBridge.startResource(
            on: self,
            resourceKey: resourceKey,
            httpMethod: httpMethod,
            urlString: urlString,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    /// Adds temporal metrics to given RUM resource.
    ///
    /// It must be called before the resource is stopped.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - metrics: the `URLSessionTaskMetrics` for this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: attributes)
    }

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - response: the `URLResepone` received for the resource.
    ///   - size: an optional size of the data received for the resource (in bytes). If not provided, it will be inferred from the "Content-Length" header of the `response`.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        response: URLResponse,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResource(
            resourceKey: resourceKey,
            response: response,
            size: size,
            attributes: attributes
        )
    }

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - statusCode: HTTP code of the response.
    ///   - kind: type of the resource.
    ///   - size: an optional size of the data received for the resource (in bytes).
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        statusCode: Int? = nil,
        kind: RUMResourceType,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResource(
            resourceKey: resourceKey,
            statusCode: statusCode,
            kind: kind,
            size: size,
            attributes: attributes
        )
    }

    /// Stops RUM resource with reporting an error.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - error: the `Error` object received when loading the resource.
    ///   - response: an optional `URLResponse` received for the resource.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResourceWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceWithError(
            resourceKey: resourceKey,
            error: error,
            response: response,
            attributes: attributes
        )
    }

    /// Stops RUM resource with reporting an error.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - message: the message explaining the Resource failure.
    ///   - type: the type of the error.
    ///   - response: an optional `URLResponse` received for the resource.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResourceWithError(
        resourceKey: String,
        message: String,
        type: String? = nil,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceWithError(
            resourceKey: resourceKey,
            message: message,
            type: type,
            response: response,
            attributes: attributes
        )
    }

    // MARK: - actions

    /// Adds RUM action.
    /// - Parameters:
    ///   - type: the type of the action.
    ///   - name: the name of the action.
    ///   - attributes: custom attributes to attach to this action.
    func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addAction(type: type, name: name, attributes: attributes)
    }

    #if os(iOS)
    /// Adds a RUM action to the current tracked view in an explicitly selected
    /// window scene.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// If the selected scene has no current tracked view, the SDK preserves the
    /// call site's inferred and process-representative fallbacks.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func addAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMActionViewTargetBridge.addAction(
            on: self,
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    /// Starts RUM action.
    ///
    /// If the action is not stopped with `stopAction(type:)`, it will be stopped automatically after 10 seconds.
    /// - Parameters:
    ///   - type: the type of the action.
    ///   - name: the name of the action.
    ///   - attributes: custom attributes to attach to this action.
    func startAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startAction(type: type, name: name, attributes: attributes)
    }

    #if os(iOS)
    /// Starts a RUM action in the current tracked view of the selected scene.
    /// The existing per-view action slot and automatic timeout still apply.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// If the selected scene has no current tracked view, the SDK preserves the
    /// call site's inferred and process-representative fallbacks.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMActionViewTargetBridge.startAction(
            on: self,
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    /// Stops RUM action.
    /// 
    /// The action must be first started with `startAction(type:)`.
    /// - Parameters:
    ///   - type: the type of the action. It should match type passed when starting this action.
    ///   - name: the name of the action. If not provided it will use the name the action was started with.
    ///   - attributes: custom attributes to attach to this action.
    func stopAction(
        type: RUMActionType,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopAction(type: type, name: name, attributes: attributes)
    }

    #if os(iOS)
    /// Stops the action in the current tracked view of the selected scene.
    /// A live view with no action leaves actions in other scenes unchanged.
    /// The name and type describe the completed action; they are not lookup keys.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// If the selected scene has no current tracked view, the SDK preserves the
    /// call site's inferred and process-representative fallbacks.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func stopAction(
        type: RUMActionType,
        name: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMActionViewTargetBridge.stopAction(
            on: self,
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    // MARK: - Operations

    /// Starts a RUM Operation.
    ///
    /// An operation is identified application-wide by its exact `name` and `operationKey`.
    /// Scenes do not namespace that identity. Use a unique key for each concurrent instance.
    /// Starting the same identity again makes the SDK track only the latest start; the earlier
    /// backend operation remains open until its four-hour timeout.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: an opaque key identifying this operation instance.
    ///     Reuse the exact value for every step.
    ///   - attributes: custom attributes to attach to this operation
    ///   - options: options to attach to this operation (e.g. profiling options)
    @available(*, message: "This API is in preview and may change in future releases")
    func startOperation(
        name: String,
        operationKey: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:],
        options: OperationOptions? = nil
    ) {
        startOperation(name: name, operationKey: operationKey, attributes: attributes, options: options)
    }

    /// Starts a Feature Operation.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: an opaque key identifying this operation instance.
    ///     Reuse the exact value for every step.
    ///   - attributes: custom attributes to attach to this operation
    @available(*, deprecated, renamed: "startOperation(name:operationKey:attributes:options:)", message: "Use startOperation(name:operationKey:attributes:options:) instead.")
    func startFeatureOperation(
        name: String,
        operationKey: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startOperation(name: name, operationKey: operationKey, attributes: attributes, options: nil)
    }

    /// Completes a RUM Operation successfully.
    ///
    /// The completion may occur in a different scene from the start. It is attributed using
    /// the view context available at this call site.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the exact key passed to `startOperation`. Together with
    ///     `name`, it identifies the operation application-wide.
    ///   - attributes: custom attributes to attach to this operation
    @available(*, message: "This API is in preview and may change in future releases")
    func succeedOperation(
        name: String,
        operationKey: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        succeedOperation(name: name, operationKey: operationKey, attributes: attributes)
    }

    /// Completes a Feature Operation successfully.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the exact key passed to `startOperation`. Together with
    ///     `name`, it identifies the operation application-wide.
    ///   - attributes: custom attributes to attach to this operation
    @available(*, deprecated, renamed: "succeedOperation(name:operationKey:attributes:)", message: "Use succeedOperation(name:operationKey:attributes:) instead.")
    func succeedFeatureOperation(
        name: String,
        operationKey: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        succeedOperation(name: name, operationKey: operationKey, attributes: attributes)
    }

    /// Fails a RUM Operation.
    ///
    /// The failure may occur in a different scene from the start. It is attributed using
    /// the view context available at this call site.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the exact key passed to `startOperation`. Together with
    ///     `name`, it identifies the operation application-wide.
    ///   - reason: the reason for the failure
    ///   - attributes: custom attributes to attach to this operation
    @available(*, message: "This API is in preview and may change in future releases")
    func failOperation(
        name: String,
        operationKey: String? = nil,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        failOperation(name: name, operationKey: operationKey, reason: reason, attributes: attributes)
    }

    #if os(iOS)
    /// Starts a RUM Operation on the current tracked view in an explicitly
    /// selected window scene.
    ///
    /// This API is experimental and may change before becoming generally available.
    /// The scene does not namespace the Operation identity: every later step must
    /// reuse the same `name` and `operationKey`.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func startOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        options: OperationOptions? = nil
    ) {
        RUMOperationViewTargetBridge.startOperation(
            on: self,
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            options: options,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Completes a RUM Operation successfully on the current tracked view in
    /// an explicitly selected window scene.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func succeedOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMOperationViewTargetBridge.succeedOperation(
            on: self,
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    /// Fails a RUM Operation on the current tracked view in an explicitly
    /// selected window scene.
    @_spi(Experimental)
    @available(iOS 27.0, *)
    @MainActor
    func failOperation(
        name: String,
        operationKey: String? = nil,
        reason: RUMFeatureOperationFailureReason,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        RUMOperationViewTargetBridge.failOperation(
            on: self,
            name: name,
            operationKey: operationKey,
            reason: reason,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
    #endif

    /// Fails a Feature Operation.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the exact key passed to `startOperation`. Together with
    ///     `name`, it identifies the operation application-wide.
    ///   - reason: the reason for the failure
    ///   - attributes: custom attributes to attach to this operation
    @available(*, deprecated, renamed: "failOperation(name:operationKey:reason:attributes:)", message: "Use failOperation(name:operationKey:reason:attributes:) instead.")
    func failFeatureOperation(
        name: String,
        operationKey: String? = nil,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        failOperation(name: name, operationKey: operationKey, reason: reason, attributes: attributes)
    }
}

#if os(iOS)
/// Private capability preserving existing custom monitor requirements.
internal protocol RUMErrorViewTargetHandling: AnyObject {
    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?,
        explicitTarget: RUMCommandTarget?
    )
    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], explicitTarget: RUMCommandTarget?)
    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler,
        explicitTarget: RUMCommandTarget?
    )
}

/// Forwards exactly once through the targeted capability or the legacy API.
@MainActor
internal enum RUMErrorViewTargetBridge {
    static func addError(
        on monitor: any RUMMonitorProtocol,
        message: String,
        type: String?,
        stack: String?,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?,
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMErrorViewTargetHandling else {
            monitor.addError(message: message, type: type, stack: stack, source: source, attributes: attributes, file: file, line: line)
            return
        }
        monitor.addError(
            message: message,
            type: type,
            stack: stack,
            source: source,
            attributes: attributes,
            file: file,
            line: line,
            explicitTarget: explicitTarget
        )
    }

    static func addError(
        on monitor: any RUMMonitorProtocol,
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMErrorViewTargetHandling else {
            monitor.addError(error: error, source: source, attributes: attributes)
            return
        }
        monitor.addError(error: error, source: source, attributes: attributes, explicitTarget: explicitTarget)
    }

    static func addError(
        on monitor: any RUMMonitorProtocol,
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler,
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMErrorViewTargetHandling else {
            monitor.addError(error: error, source: source, attributes: attributes, completionHandler: completionHandler)
            return
        }
        monitor.addError(
            error: error, source: source, attributes: attributes, completionHandler: completionHandler, explicitTarget: explicitTarget
        )
    }
}
#endif

#if os(iOS)
/// Private capability preserving existing custom monitor requirements.
internal protocol RUMResourceViewTargetHandling: AnyObject {
    func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )

    func startResource(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )

    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )
}

/// Forwards exactly once through the targeted capability or the legacy API.
@MainActor
internal enum RUMResourceViewTargetBridge {
    static func startResource(
        on monitor: any RUMMonitorProtocol,
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMResourceViewTargetHandling else {
            monitor.startResource(resourceKey: resourceKey, request: request, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            request: request,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }

    static func startResource(
        on monitor: any RUMMonitorProtocol,
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMResourceViewTargetHandling else {
            monitor.startResource(resourceKey: resourceKey, url: url, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            url: url,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }

    static func startResource(
        on monitor: any RUMMonitorProtocol,
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMResourceViewTargetHandling else {
            monitor.startResource(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            httpMethod: httpMethod,
            urlString: urlString,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }
}
#endif

#if os(iOS)
/// Private capability used by extension-only action overloads so existing
/// third-party `RUMMonitorProtocol` conformers do not gain a new requirement.
internal protocol RUMActionViewTargetHandling: AnyObject {
    func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )
    func startAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )

    func stopAction(
        type: RUMActionType,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )
}

/// Dispatches an explicit action target when the SDK monitor supports it and
/// otherwise calls the existing inferred API exactly once.
@MainActor
internal enum RUMActionViewTargetBridge {
    static func addAction(
        on monitor: any RUMMonitorProtocol,
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMActionViewTargetHandling else {
            monitor.addAction(type: type, name: name, attributes: attributes)
            return
        }

        monitor.addAction(
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }
    static func startAction(
        on monitor: any RUMMonitorProtocol,
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMActionViewTargetHandling else {
            monitor.startAction(type: type, name: name, attributes: attributes)
            return
        }

        monitor.startAction(
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }

    static func stopAction(
        on monitor: any RUMMonitorProtocol,
        type: RUMActionType,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMActionViewTargetHandling else {
            monitor.stopAction(type: type, name: name, attributes: attributes)
            return
        }

        monitor.stopAction(
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }
}

/// Private capability used by extension-only Operation overloads so existing
/// third-party `RUMMonitorProtocol` conformers do not gain a new requirement.
internal protocol RUMOperationViewTargetHandling: AnyObject {
    func startOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        options: OperationOptions?,
        explicitTarget: RUMCommandTarget?
    )

    func succeedOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )

    func failOperation(
        name: String,
        operationKey: String?,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    )
}

/// Dispatches explicit Operation targets when the SDK monitor supports them and
/// otherwise calls the existing inferred API exactly once.
@MainActor
internal enum RUMOperationViewTargetBridge {
    static func startOperation(
        on monitor: any RUMMonitorProtocol,
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        options: OperationOptions?,
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMOperationViewTargetHandling else {
            monitor.startOperation(
                name: name,
                operationKey: operationKey,
                attributes: attributes,
                options: options
            )
            return
        }

        monitor.startOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            options: options,
            explicitTarget: explicitTarget
        )
    }

    static func succeedOperation(
        on monitor: any RUMMonitorProtocol,
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMOperationViewTargetHandling else {
            monitor.succeedOperation(
                name: name,
                operationKey: operationKey,
                attributes: attributes
            )
            return
        }

        monitor.succeedOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }

    static func failOperation(
        on monitor: any RUMMonitorProtocol,
        name: String,
        operationKey: String?,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget
    ) {
        guard let monitor = monitor as? any RUMOperationViewTargetHandling else {
            monitor.failOperation(
                name: name,
                operationKey: operationKey,
                reason: reason,
                attributes: attributes
            )
            return
        }

        monitor.failOperation(
            name: name,
            operationKey: operationKey,
            reason: reason,
            attributes: attributes,
            explicitTarget: explicitTarget
        )
    }
}

/// Keeps extension-only scene APIs source-compatible with third-party monitor
/// conformers while allowing the SDK monitor to use exact scene ownership.
@MainActor
internal enum RUMSceneTargetedManualViewBridge {
    static func startView(
        on monitor: any RUMMonitorViewProtocol,
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        guard let monitor = monitor as? any RUMSceneTargetedManualViewHandling else {
            monitor.startView(key: key, name: name, attributes: attributes)
            return
        }

        monitor.startView(
            key: key,
            name: name,
            attributes: attributes,
            sceneIdentifier: sceneIdentifier
        )
    }

    static func stopView(
        on monitor: any RUMMonitorViewProtocol,
        key: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        guard let monitor = monitor as? any RUMSceneTargetedManualViewHandling else {
            monitor.stopView(key: key, attributes: attributes)
            return
        }

        monitor.stopView(
            key: key,
            attributes: attributes,
            sceneIdentifier: sceneIdentifier
        )
    }
}
#endif

// swiftlint:enable function_default_parameter_at_end
