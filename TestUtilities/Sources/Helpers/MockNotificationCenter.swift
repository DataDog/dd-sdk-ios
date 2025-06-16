/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

final class MockNotificationCenter: NotificationCenter, @unchecked Sendable {
        private(set) var observers: [(name: Notification.Name?, object: Any?, queue: OperationQueue?, block: (Notification) -> Void)] = []

        override func addObserver(forName name: Notification.Name?, object: Any?, queue: OperationQueue?, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            let observer = NSObject()
            observers.append((name, object, queue, block))
            return observer
        }

        func postFakeNotification(name: Notification.Name) {
            for observer in observers where observer.name == name {
                observer.block(Notification(name: name))
            }
        }

        func getObserverNames() -> [Notification.Name] {
            observers.compactMap(\.name)
        }
    }
