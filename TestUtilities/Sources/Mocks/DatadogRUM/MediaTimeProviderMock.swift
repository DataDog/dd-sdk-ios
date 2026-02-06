/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import DatadogRUM
import Foundation
import QuartzCore

/// Mock to return media uptime.
public final class MediaTimeProviderMock: CACurrentMediaTimeProvider {
    private let _current: ReadWriteLock<CFTimeInterval>

    #if os(watchOS)
    public init(current: CFTimeInterval = 0) {
        self._current = .init(wrappedValue: current)
    }
    #else
    public init(current: CFTimeInterval = CACurrentMediaTime()) {
        self._current = .init(wrappedValue: current)
    }
    #endif

    public var current: CFTimeInterval {
        get { _current.wrappedValue }
        set { _current.wrappedValue = newValue }
    }
}
