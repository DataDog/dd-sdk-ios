/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An observer for `UserInfo` value.
internal typealias UserInfoObserver = ValueObserver

/// Provides the current `UserInfo` value and notifies all subscribers on its change.
internal class UserInfoProvider {
    private let publisher: ValuePublisher<UserInfo>

    init() {
        let emptyUserInfo = UserInfo(id: nil, name: nil, email: nil, extraInfo: [:])
        // Synchronous `updatesModel` makes the `value` setter a blocking call.
        // This ensures that the new value of the `UserInfo`` will be applied immediately
        // to all data sent from the the same thread.
        self.publisher = ValuePublisher(initialValue: emptyUserInfo, updatesModel: .synchronous)
    }

    // MARK: - `UserInfo` Value

    var value: UserInfo {
        set { publisher.currentValue = newValue }
        get { publisher.currentValue }
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: UserInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == UserInfo {
        publisher.subscribe(subscriber)
    }
}

/// Information about the user.
internal struct UserInfo {
    let id: String?
    let name: String?
    let email: String?
    let extraInfo: [AttributeKey: AttributeValue]
}
