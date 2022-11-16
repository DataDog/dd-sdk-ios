/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides a thread-safe access to server time offset.
internal class ServerDateCorrector: DateCorrector {
    /// Server offset publisher.
    private let publisher: ValuePublisher<TimeInterval> = ValuePublisher(initialValue: 0)
    private let provider: ServerDateProvider

    init(serverDateProvider: ServerDateProvider) {
        self.provider = serverDateProvider
        serverDateProvider.synchronize(update: publisher.publishAsync)
    }

    var offset: TimeInterval {
        return publisher.currentValue
    }
}
