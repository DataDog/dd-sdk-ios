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
        self.publisher = ValuePublisher(initialValue: .empty)
    }

    // MARK: - `UserInfo` Value

    var value: UserInfo {
        set {
            // Synchronous update ensures that the new value of the user info will be applied immediately
            // to all data sent from the the same thread.
            publisher.publishSync(newValue)
        }
        get { publisher.currentValue }
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: UserInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == UserInfo {
        publisher.subscribe(subscriber)
    }
}

public struct UserInfo {
    /// User ID, if any.
    public let id: String?
    /// Name representing the user, if any.
    public let name: String?
    /// User email, if any.
    public let email: String?
    /// User custom attributes, if any.
    public var extraInfo: [AttributeKey: AttributeValue]
}

extension UserInfo {
    internal static var empty: Self {
        .init(
            id: nil,
            name: nil,
            email: nil,
            extraInfo: [:]
        )
    }
}
