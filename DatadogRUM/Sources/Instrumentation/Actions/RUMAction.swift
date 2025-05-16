/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// A description of the RUM Action returned from the `UIKitRUMActionsPredicate`.
public struct RUMAction {
    /// The RUM Action name, appearing as `ACTION NAME` in RUM Explorer. If no name is given, default one will be used.
    public var name: String

    /// Additional attributes to associate with the RUM Action.
    public var attributes: [AttributeKey: AttributeValue]

    /// Initializes the RUM Action description.
    /// - Parameters:
    ///   - name: the RUM Action name, appearing as `Action NAME` in RUM Explorer. If no name is given, default one will be used.
    ///   - attributes: additional attributes to associate with the RUM Action.
    public init(name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = name
        self.attributes = attributes
    }
}
