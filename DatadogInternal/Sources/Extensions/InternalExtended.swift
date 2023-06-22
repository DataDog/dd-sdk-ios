/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Type that acts as a generic extension point for all `InternalExtended` types.
public struct InternalExtension<ExtendedType> {

    /// Stores the type or meta-type of any extended type.
    public var type: ExtendedType

    /// Create an instance from the provided value.
    ///
    /// - Parameter type: Instance being extended.
    public init(_ type: ExtendedType) {
        self.type = type
    }
}

/// Protocol describing the `_internal` extension points for internal extended types.
public protocol InternalExtended {
    /// Type being extended.
    associatedtype ExtendedType

    /// Static internal extension point.
    static var _internal: InternalExtension<ExtendedType>.Type { get }

    /// Instance internal extension point.
    var _internal: InternalExtension<ExtendedType> { get }

    /// Instance internal mutation point.
    mutating func _internal_mutation(_ mutation: (inout InternalExtension<ExtendedType>) -> Void)
}

extension InternalExtended {
    /// Grants access to an internal interface utilized only by other Datadog SDKs.
    /// **It is not meant for public use** and it might change without prior notice.
    public static var _internal: InternalExtension<Self>.Type {
        InternalExtension<Self>.self
    }

    /// Instance internal extension point.
    public var _internal: InternalExtension<Self> {
        InternalExtension(self)
    }

    /// Instance internal mutaion point.
    public mutating func _internal_mutation(_ mutation: (inout InternalExtension<Self>) -> Void) {
        var mutating = InternalExtension(self)
        mutation(&mutating)
        self = mutating.type
    }
}
