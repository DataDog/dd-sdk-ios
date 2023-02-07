/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type, writing data.
public protocol Writer {
    func write<T: Encodable>(value: T)
}

public struct NOPWriter: Writer {
    public init() { }

    public func write<T>(value: T) where T: Encodable {}
}
