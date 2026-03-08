/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)
import UIKit

/// Produces screen brightness level updates via `AsyncStream` by observing
/// `UIScreen.brightnessDidChangeNotification`.
internal struct BrightnessLevelSource: ContextValueSource {
    let initialValue: BrightnessLevel?
    let values: AsyncStream<BrightnessLevel?>

    init(notificationCenter: NotificationCenter = .default, screen: UIScreen? = nil) {
        let screen = screen ?? MainActor.assumeIsolated { UIScreen.main }
        self.initialValue = Float(screen.brightness)

        self.values = AsyncStream { continuation in
            nonisolated(unsafe) let observer = notificationCenter.addObserver(
                forName: UIScreen.brightnessDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield(Float(screen.brightness))
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }
}

#endif
