/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Objective-C extension for subscribing to Datadog context updates.
///
/// This class provides cross-platform libraries with the ability to receive real-time updates
/// to the Datadog shared context from Objective-C code.
///
/// Note: It only works for single core setup, relying on `CoreRegistry.default` existence.
@objc(DDCrossPlatformExtension)
@objcMembers
@_spi(Internal)
public final class CrossPlatformExtension: NSObject {
    private static var contextSharingTransformer: ContextSharingTransformer?

    /// Subscribes to shared context updates.
    ///
    /// The provided closure will be called immediately with the current context (or `nil` if no context yet),
    /// and subsequently whenever the context changes.
    ///
    /// - Parameter toSharedContext: A closure that receives `SharedContext` updates. Called on context changes.
    @objc
    public static func subscribe(toSharedContext: @escaping (SharedContext?) -> Void) {
        if Self.contextSharingTransformer == nil {
            let core = CoreRegistry.default
            let contextSharingTransformer = ContextSharingTransformer()
            try? core.register(feature: ContextSharingFeature(messageReceiver: contextSharingTransformer))
            Self.contextSharingTransformer = contextSharingTransformer
        }
        contextSharingTransformer?.publish(to: toSharedContext)
    }

    @objc
    public static func unsubscribeFromSharedContext() {
        contextSharingTransformer = nil
    }
}
