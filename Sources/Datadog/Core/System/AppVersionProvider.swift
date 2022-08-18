/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the app version.
internal final class AppVersionProvider {
    private let publisher: ValuePublisher<String>

    init(configuration: CoreConfiguration) {
        self.publisher = ValuePublisher(initialValue: configuration.applicationVersion)
    }

    var value: String {
        set { publisher.publishSync(newValue) }
        get { publisher.currentValue }
    }
}
