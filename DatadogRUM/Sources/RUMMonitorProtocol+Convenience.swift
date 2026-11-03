/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import DatadogInternal

// swiftlint:disable function_default_parameter_at_end

#if os(iOS)
/// Manual scene methods are isolated individually so Monitor stays nonisolated.
internal protocol RUMManualViewTargetHandling: AnyObject {
    @MainActor
    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue], sceneIdentifier: RUMSceneIdentifier)
    @MainActor
    func stopView(key: String, attributes: [AttributeKey: AttributeValue], sceneIdentifier: RUMSceneIdentifier)
}

internal protocol RUMFeatureFlagTargetHandling: AnyObject {
    func addFeatureFlagEvaluation(name: String, value: Encodable, explicitTarget: RUMCommandTarget?)
}

internal protocol RUMViewTimingTargetHandling: AnyObject {
    func addTiming(name: String, explicitTarget: RUMCommandTarget?)
    func addViewLoadingTime(overwrite: Bool, explicitTarget: RUMCommandTarget?)
}

internal protocol RUMViewAttributeTargetHandling: AnyObject {
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue, explicitTarget: RUMCommandTarget?)
    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue], explicitTarget: RUMCommandTarget?)
    func removeViewAttribute(forKey key: AttributeKey, explicitTarget: RUMCommandTarget?)
    func removeViewAttributes(forKeys keys: [AttributeKey], explicitTarget: RUMCommandTarget?)
}

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

    #if os(macOS)
    /// Starts RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `NSViewController` representing this view.
    ///   - name: the name of the view. If not provided, the `viewController` class name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        viewController: NSViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(viewController: viewController, name: name, attributes: attributes)
    }

    /// Stops RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `NSViewController` representing this view.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        viewController: NSViewController,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(viewController: viewController, attributes: attributes)
    }
    #elseif !os(watchOS)
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

    // MARK: - Operations

    /// Starts a RUM Operation.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation)
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
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation)
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
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation); it should be provided if `operationKey` was provided when invoking `startOperation`
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
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation); it should be provided if `operationKey` was provided when invoking `startOperation`
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
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation); it should be provided if `operationKey` was provided when invoking `startOperation`
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

    /// Fails a Feature Operation.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation); it should be provided if `operationKey` was provided when invoking `startOperation`
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

// swiftlint:enable function_default_parameter_at_end

// swiftlint:disable function_default_parameter_at_end

#if os(iOS)
/// Selects the RUM view used to attribute explicitly targeted telemetry.
/// Unsupported scene targeting preserves the receiving monitor’s legacy behavior.
///
/// This API is experimental and may change before becoming generally available.
/// It does not expose or retain an internal RUM view identifier.
@_spi(Experimental)
@available(iOS 15.0, *)
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
@available(iOS 15.0, *)
public typealias RUMOperationViewTarget = RUMViewTarget
#endif

#if os(iOS)

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

public extension RUMMonitorProtocol {
    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addFeatureFlagEvaluation(name: String, value: Encodable, view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMFeatureFlagTargetHandling else {
            addFeatureFlagEvaluation(name: name, value: value)
            return
        }
        monitor.addFeatureFlagEvaluation(name: name, value: value, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startView(
        key: String,
        name: String? = nil,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMManualViewTargetHandling else {
            startView(key: key, name: name, attributes: attributes)
            return
        }
        monitor.startView(
            key: key,
            name: name,
            attributes: attributes,
            sceneIdentifier: RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func stopView(
        key: String,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMManualViewTargetHandling else {
            stopView(key: key, attributes: attributes)
            return
        }
        monitor.stopView(
            key: key,
            attributes: attributes,
            sceneIdentifier: RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
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
        guard #available(iOS 27.0, *), let monitor = self as? any RUMErrorViewTargetHandling else {
            addError(message: message, type: type, stack: stack, source: source, attributes: attributes, file: file, line: line)
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
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMErrorViewTargetHandling else {
            addError(error: error, source: source, attributes: attributes)
            return
        }
        monitor.addError(error: error, source: source, attributes: attributes, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        completionHandler: @escaping CompletionHandler
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMErrorViewTargetHandling else {
            addError(error: error, source: source, attributes: attributes, completionHandler: completionHandler)
            return
        }
        monitor.addError(
            error: error,
            source: source,
            attributes: attributes,
            completionHandler: completionHandler,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        request: URLRequest,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMResourceViewTargetHandling else {
            startResource(resourceKey: resourceKey, request: request, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            request: request,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        url: URL,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMResourceViewTargetHandling else {
            startResource(resourceKey: resourceKey, url: url, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            url: url,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMResourceViewTargetHandling else {
            startResource(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes)
            return
        }
        monitor.startResource(
            resourceKey: resourceKey,
            httpMethod: httpMethod,
            urlString: urlString,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMActionViewTargetHandling else {
            addAction(type: type, name: name, attributes: attributes)
            return
        }
        monitor.addAction(type: type, name: name, attributes: attributes, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMActionViewTargetHandling else {
            startAction(type: type, name: name, attributes: attributes)
            return
        }
        monitor.startAction(type: type, name: name, attributes: attributes, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func stopAction(
        type: RUMActionType,
        name: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMActionViewTargetHandling else {
            stopAction(type: type, name: name, attributes: attributes)
            return
        }
        monitor.stopAction(type: type, name: name, attributes: attributes, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func startOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        options: OperationOptions? = nil
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMOperationViewTargetHandling else {
            startOperation(name: name, operationKey: operationKey, attributes: attributes, options: options)
            return
        }
        monitor.startOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            options: options,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func succeedOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMOperationViewTargetHandling else {
            succeedOperation(name: name, operationKey: operationKey, attributes: attributes)
            return
        }
        monitor.succeedOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func failOperation(
        name: String,
        operationKey: String? = nil,
        reason: RUMFeatureOperationFailureReason,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMOperationViewTargetHandling else {
            failOperation(name: name, operationKey: operationKey, reason: reason, attributes: attributes)
            return
        }
        monitor.failOperation(
            name: name,
            operationKey: operationKey,
            reason: reason,
            attributes: attributes,
            explicitTarget: .scene(view.sceneIdentifier)
        )
    }
}

public extension RUMMonitorViewProtocol {
    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addTiming(name: String, view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewTimingTargetHandling else {
            addTiming(name: name)
            return
        }
        monitor.addTiming(name: name, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addViewLoadingTime(overwrite: Bool, view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewTimingTargetHandling else {
            addViewLoadingTime(overwrite: overwrite)
            return
        }
        monitor.addViewLoadingTime(overwrite: overwrite, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue, view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewAttributeTargetHandling else {
            addViewAttribute(forKey: key, value: value)
            return
        }
        monitor.addViewAttribute(forKey: key, value: value, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue], view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewAttributeTargetHandling else {
            addViewAttributes(attributes)
            return
        }
        monitor.addViewAttributes(attributes, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func removeViewAttribute(forKey key: AttributeKey, view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewAttributeTargetHandling else {
            removeViewAttribute(forKey: key)
            return
        }
        monitor.removeViewAttribute(forKey: key, explicitTarget: .scene(view.sceneIdentifier))
    }

    @_spi(Experimental)
    @available(iOS 15.0, *)
    @MainActor
    func removeViewAttributes(forKeys keys: [AttributeKey], view: RUMViewTarget) {
        guard #available(iOS 27.0, *), let monitor = self as? any RUMViewAttributeTargetHandling else {
            removeViewAttributes(forKeys: keys)
            return
        }
        monitor.removeViewAttributes(forKeys: keys, explicitTarget: .scene(view.sceneIdentifier))
    }
}
#endif

// swiftlint:enable function_default_parameter_at_end
