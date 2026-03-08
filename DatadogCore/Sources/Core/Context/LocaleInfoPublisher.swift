/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Produces `LocaleInfo` updates via `AsyncStream` by observing
/// `NSLocale.currentLocaleDidChangeNotification`.
internal struct LocaleInfoSource: ContextValueSource, @unchecked Sendable {
    let initialValue: LocaleInfo
    let values: AsyncStream<LocaleInfo>

    init(initialLocale: LocaleInfo, notificationCenter: NotificationCenter) {
        self.initialValue = initialLocale

        self.values = AsyncStream { continuation in
            nonisolated(unsafe) let observer = notificationCenter
                .addObserver(
                    forName: NSLocale.currentLocaleDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    continuation.yield(LocaleInfo())
                }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }
}
