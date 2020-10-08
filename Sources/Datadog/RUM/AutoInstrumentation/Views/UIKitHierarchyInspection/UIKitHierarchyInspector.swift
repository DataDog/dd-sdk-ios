/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// Inspects the view controllers hierarchy of the current window and finds
/// the `UIViewController` which is currently displayed to the user.
internal protocol UIKitHierarchyInspectorType {
    func topViewController() -> UIViewController?
}

internal struct UIKitHierarchyInspector: UIKitHierarchyInspectorType {
    func topViewController() -> UIViewController? {
        return nil
    }
}
