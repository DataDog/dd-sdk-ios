/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public protocol Configuration {
    /// Return a Configuration object of type T.
    ///
    /// - Parameters:
    ///   - type: The configuration type.
    ///   - key: The configuration key.
    /// - Returns: The configuration object if available.
    func property<T>(_ type: T.Type, forKey key: String) -> T? where T: Decodable
}
