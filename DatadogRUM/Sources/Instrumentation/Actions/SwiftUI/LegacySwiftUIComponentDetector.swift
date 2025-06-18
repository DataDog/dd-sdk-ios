/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal

internal final class LegacySwiftUIComponentDetector: SwiftUIComponentDetector {
    func createActionCommand(
        from touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        guard let predicate,
              touch.phase == .ended else {
            return nil
        }

        if let view = touch.view,
           view.isSwiftUIView,
           // For iOS 17 and below, we can't reliably distinguish SwiftUI component types (e.g., Button vs Label).
           // We exclude hosting views and track other SwiftUI elements with a generic name.
           !SwiftUIContainerViews.shouldIgnore(view.typeDescription) {
            let refinedName = SwiftUIComponentHelpers.extractComponentName(
                touch: touch,
                defaultName: SwiftUIComponentNames.unidentified
            )

            if let rumAction = predicate.rumAction(with: refinedName) {
                return RUMAddUserActionCommand(
                    time: dateProvider.now,
                    attributes: rumAction.attributes,
                    instrumentation: .swiftuiAutomatic,
                    actionType: .tap,
                    name: rumAction.name
                )
            }
        }

        // Special detection for SwiftUI Toogle
        return SwiftUIComponentHelpers.extractSwiftUIToggleAction(
            from: touch,
            predicate: predicate,
            dateProvider: dateProvider
        )
    }
}

private enum SwiftUIContainerViews {
    /// SwiftUI container views that should be ignored for action tracking
    /// to avoid duplicate events and noise
    static let ignoredTypeDescriptions: Set<String> = [
        "HostingView",
        "HostingScrollView",
        "PlatformGroupContainer"
    ]

    static func shouldIgnore(_ typeDescription: String) -> Bool {
        return ignoredTypeDescriptions.contains { typeDescription.contains($0) }
    }
}
