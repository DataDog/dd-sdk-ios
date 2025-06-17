/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)
import UIKit

/// A publisher that publishes the screen brightness level from UIScreen.
internal final class BrightnessStatusPublisher: ContextValuePublisher {
    /// The initial brightness level.
    let initialValue: BrightnessStatus?

    /// The notification center to observe brightness changes.
    private let notificationCenter: NotificationCenter
    private let screen: UIScreen
    private var observers: [Any]? = nil

    init(notificationCenter: NotificationCenter = .default, screen: UIScreen = .main) {
        self.notificationCenter = notificationCenter
        self.screen = screen
        self.initialValue = BrightnessStatus(level: Float(screen.brightness))
    }

    /// Publishes the brightness level to the given receiver.
    ///
    /// - Parameter receiver: The receiver to publish the brightness level to.
    func publish(to receiver: @escaping ContextValueReceiver<BrightnessStatus?>) {
        let block = { (notification: Notification) in
            receiver(BrightnessStatus(level: Float(self.screen.brightness)))
        }

        observers = [
            notificationCenter.addObserver(
                forName: UIScreen.brightnessDidChangeNotification,
                object: nil,
                queue: .main,
                using: block
            )
        ]

        receiver(initialValue)
    }

    func cancel() {
        observers?.forEach(notificationCenter.removeObserver)
        observers = nil
    }
}

#endif
