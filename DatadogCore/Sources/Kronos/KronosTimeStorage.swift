/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import Foundation

/// Defines where the user defaults are stored
internal enum KronosTimeStoragePolicy {
    /// Uses `UserDefaults.Standard`
    case standard
    /// Attempts to use the specified App Group ID (which is the String) to access shared storage.
    case appGroup(String)

    /// Creates an instance
    ///
    /// - parameter appGroupID: The App Group ID that maps to a shared container for `UserDefaults`. If this
    ///                         is nil, the resulting instance will be `.standard`
    init(appGroupID: String?) {
        if let appGroupID = appGroupID {
            self = .appGroup(appGroupID)
        } else {
            self = .standard
        }
    }
}

/// Handles saving and retrieving instances of `KronosTimeFreeze` for quick retrieval
internal struct KronosTimeStorage {
    private var userDefaults: UserDefaults // swiftlint:disable:this required_reason_api_name
    private let kDefaultsKey = "KronosStableTime"

    /// The most recent stored `TimeFreeze`. Getting retrieves from the UserDefaults defined by the storage
    /// policy. Setting sets the value in UserDefaults
    var stableTime: KronosTimeFreeze? {
        get {
            guard let stored = self.userDefaults.value(forKey: kDefaultsKey) as? [String: TimeInterval],
                let previousStableTime = KronosTimeFreeze(from: stored) else {
                return nil
            }

            return previousStableTime
        }

        set {
            guard let newFreeze = newValue else {
                return
            }

            self.userDefaults.set(newFreeze.toDictionary(), forKey: kDefaultsKey)
        }
    }

    /// Creates an instance
    ///
    /// - parameter storagePolicy: Defines the storage location of `UserDefaults`
    init(storagePolicy: KronosTimeStoragePolicy) {
        switch storagePolicy {
        case .standard:
            self.userDefaults = .standard
        case .appGroup(let groupName):
            let sharedDefaults = UserDefaults(suiteName: groupName) // swiftlint:disable:this required_reason_api_name
            assert(sharedDefaults != nil, "Could not create UserDefaults for group: '\(groupName)'")
            self.userDefaults = sharedDefaults ?? .standard
        }
    }
}
