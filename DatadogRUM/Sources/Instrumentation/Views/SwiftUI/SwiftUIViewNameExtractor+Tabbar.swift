/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

extension SwiftUIReflectionBasedViewNameExtractor {
    // MARK: - String Parsing
    @usableFromInline
    internal func extractTabViewName(viewController: UIViewController) -> String? {
        // We fetch the parent, which corresponds to the TabBarController
        guard let parent = viewController.parent as? UITabBarController,
              let container = parent.parent else {
            return nil
        }

        let selectedIndex = parent.selectedIndex
        let containerReflector = Reflector(subject: container, telemetry: NOPTelemetry())

        if let output = extractHostingControllerPath(with: containerReflector),
           let containerViewName = extractViewNameFromHostingViewController(output) {
            return "\(containerViewName)_index_\(selectedIndex)"
        }

        return nil
    }
}
