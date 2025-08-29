/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import QuartzCore

/// Mock to return media uptime.
public final class MediaTimeProviderMock: MediaTimeProvider {
    private let _now: ReadWriteLock<CFTimeInterval>

    public init(now: CFTimeInterval = CACurrentMediaTime()) {
        self._now = .init(wrappedValue: now)
    }

    public var now: CFTimeInterval {
        get { _now.wrappedValue }
        set { _now.wrappedValue = newValue }
    }
}
