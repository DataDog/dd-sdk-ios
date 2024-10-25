/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// A protocol that provides access to the current application state.
/// See: https://developer.apple.com/documentation/uikit/uiapplication/state
public protocol AppStateProvider: Sendable {
    /// The current application state.
    ///
    /// **Note**: Must be called on the main thread.
    var current: AppState { get }
}

#if canImport(UIKit)

import UIKit

public struct DefaultAppStateProvider: AppStateProvider {
    public init() {}

    /// Gets the current application state.
    ///
    /// **Note**: Must be called on the main thread.
    public var current: AppState {
        let uiKitState = UIApplication.dd.managedShared?.applicationState ?? .active // fallback to most expected state
        return AppState(uiKitState)
    }
}

#endif

#if canImport(WatchKit)

import WatchKit

public struct DefaultAppStateProvider: AppStateProvider {
    public init() {}

    /// Gets the current application state.
    ///
    /// **Note**: Must be called on the main thread.
    public var current: AppState {
        let wkState = WKExtension.dd.shared.applicationState
        return AppState(wkState)
    }
}

#endif
