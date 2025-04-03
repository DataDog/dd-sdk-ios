/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// A description of the RUM View returned from the predicate.
public struct RUMView {
    /// The RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    public var name: String

    /// The RUM View path, appearing as `VIEW PATH GROUP` / `VIEW URL` in RUM Explorer.
    /// If set `nil`, the view controller class name will be used.
    public var path: String?

    /// Additional attributes to associate with the RUM View.
    public var attributes: [AttributeKey: AttributeValue]

    /// Whether this view is modal, but should not be tracked with `startView` and `stopView`
    /// When this is `true`, the view previous to this one will be stopped, but this one will not be
    /// started. When this view is dismissed, the previous view will be started.
    public var isUntrackedModal: Bool

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - path: the RUM View path, appearing as `PATH` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    @available(*, deprecated, message: "This initializer is renamed to `init(name:attributes:)`.")
    public init(path: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = path
        self.path = path
        self.attributes = attributes
        self.isUntrackedModal = false
    }

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - name: the RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    ///   - isUntrackedModal: true if this view is modal, but should not call startView / stopView.
    public init(name: String, attributes: [AttributeKey: AttributeValue] = [:], isUntrackedModal: Bool = false) {
        self.name = name
        self.path = nil // the "VIEW URL" will default to view controller class name
        self.attributes = attributes
        self.isUntrackedModal = isUntrackedModal
    }
}
