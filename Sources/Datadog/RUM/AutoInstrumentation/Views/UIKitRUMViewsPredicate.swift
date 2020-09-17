/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

// TODO: RUMM-713 Add public API comment
public struct RUMViewFromPredicate {
    // TODO: RUMM-726 Rename to `RUMView` when this name is no longer taken by auto-generated model(s).
    public var name: String
    public var attributes: [AttributeKey: AttributeValue]

    public init(name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = name
        self.attributes = attributes
    }
}

// TODO: RUMM-713 Add public API comment
public protocol UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMViewFromPredicate?
}
