/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Objective-C compatible wrapper for `DatadogContextSubscriber`.
///
/// This class provides a bridge to subscribe to DatadogContext updates from Objective-C code.
/// The context is exposed as `objc_DatadogContext` which is Objective-C compatible.
@objc(DDDatadogContextSubscriber)
@objcMembers
@_spi(objc)
public final class objc_DatadogContextSubscriber: NSObject {
    /// The underlying Swift subscriber.
    private let subscriber: DatadogContextSubscriber

    /// The current DatadogContext as an Objective-C compatible object.
    ///
    /// This property provides access to the `objc_DatadogContext` which wraps the Swift `DatadogContext`.
    /// Access is thread-safe.
    @objc public var context: objc_DatadogContext? {
        subscriber.context.map { objc_DatadogContext(swiftContext: $0) }
    }

    /// Creates a new instance of `objc_DatadogContextSubscriber`.
    ///
    /// - Parameter onContextUpdate: Optional callback invoked when the context is updated.
    ///   The callback receives the `objc_DatadogContext` object.
    @objc
    public init(onContextUpdate: ((objc_DatadogContext) -> Void)? = nil) {
        self.subscriber = DatadogContextSubscriber(onContextUpdate: onContextUpdate.map { callback in
            { swiftContext in
                callback(objc_DatadogContext(swiftContext: swiftContext))
            }
        })
        super.init()
    }

    /// Sets or updates the callback invoked when the context is updated.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// - Parameter callback: The callback to invoke when context is updated.
    ///   The callback receives the `objc_DatadogContext` object.
    @objc
    public func setOnContextUpdate(_ callback: @escaping (objc_DatadogContext) -> Void) {
        subscriber.setOnContextUpdate { swiftContext in
            callback(objc_DatadogContext(swiftContext: swiftContext))
        }
    }

    /// Returns the underlying `FeatureMessageReceiver` for registration with the message bus.
    ///
    /// Use this property to register the subscriber with a Datadog Feature.
    /// Note: This property is not @objc compatible as it returns a protocol type.
    public var messageReceiver: FeatureMessageReceiver {
        subscriber
    }
}
