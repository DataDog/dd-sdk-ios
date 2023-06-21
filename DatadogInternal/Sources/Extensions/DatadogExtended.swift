/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by Alamofire Software Foundation (http://alamofire.org/) and altered by Datadog.
 * Use of this source code is governed by MIT License: https://github.com/Alamofire/Alamofire/blob/master/LICENSE
 */

import Foundation

/// Type that acts as a generic extension point for all `DatadogExtended` types.
public struct DatadogExtension<ExtendedType> {
    /// Stores the type or meta-type of any extended type.
    public private(set) var type: ExtendedType

    /// Create an instance from the provided value.
    ///
    /// - Parameter type: Instance being extended.
    public init(_ type: ExtendedType) {
        self.type = type
    }
}

/// Protocol describing the `dd` extension points for Datadog extended types.
public protocol DatadogExtended {
    /// Type being extended.
    associatedtype ExtendedType

    /// Static Datadog extension point.
    static var dd: DatadogExtension<ExtendedType>.Type { get set }
    /// Instance Datadog extension point.
    var dd: DatadogExtension<ExtendedType> { get set }
}

extension DatadogExtended {
    /// Static Datadog extension point.
    public static var dd: DatadogExtension<Self>.Type {
        get { DatadogExtension<Self>.self }
        set {}
    }

    /// Instance Datadog extension point.
    public var dd: DatadogExtension<Self> {
        get { DatadogExtension(self) }
        set {}
    }
}
