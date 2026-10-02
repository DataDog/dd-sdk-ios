/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

#if canImport(WatchKit)

import WatchKit

/// Default provider for WatchOS.
///
/// See: https://developer.apple.com/documentation/watchkit/wkapplication/applicationstate
internal struct DefaultAppStateProvider: AppStateProvider {
    init() {}

    /// Gets the current application state.
    var current: AppState {
        return AppState(WKApplication.shared().applicationState)
    }
}

extension AppState {
    init(_ state: WKApplicationState) {
        switch state {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default:
            self = .active // in case a new state is introduced, default to most expected state
        }
    }
}

#elseif canImport(UIKit)

import UIKit

/// Default app state provider for iOS.
///
/// See: https://developer.apple.com/documentation/uikit/uiapplication/state
internal struct DefaultAppStateProvider: AppStateProvider {
    init() {}

    /// Gets the current application state.
    var current: AppState {
        let uiKitState = UIApplication.dd.managedShared?.applicationState ?? .active // fallback to most expected state
        return AppState(uiKitState)
    }
}

extension AppState {
    init(_ state: UIApplication.State) {
        switch state {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .active // in case a new state is introduced, default to most expected state
        }
    }
}

#endif
