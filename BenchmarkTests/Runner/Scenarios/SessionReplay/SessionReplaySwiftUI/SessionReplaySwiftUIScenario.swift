/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import SwiftUI

import DatadogCore
import DatadogRUM
import DatadogSessionReplay

import CatalogSwiftUI

struct SessionReplaySwiftUIScenario: Scenario {
    var initialViewController: UIViewController {
        UIHostingController(
            rootView: CatalogSwiftUI.ContentView()
                .environment(\.datadogMonitor, DatadogMonitor())
        )
    }

    func instrument(with info: AppInfo) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        RUM.enable(
            with: RUM.Configuration(
                applicationID: info.applicationID
            )
        )

        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                textAndInputPrivacyLevel: .maskSensitiveInputs,
                imagePrivacyLevel: .maskNone,
                touchPrivacyLevel: .show,
                featureFlags: [
                    .swiftui: true,
                    .screenChangeScheduling: true
                ]
            )
        )

        RUMMonitor.shared().addAttribute(forKey: "scenario", value: "SessionReplaySwiftUI")
    }
}

private struct DatadogMonitor: CatalogSwiftUI.DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier {
        AnyViewModifier { content in
            content.trackRUMView(name: name)
        }
    }

    func actionModifier(name: String) -> AnyViewModifier {
        AnyViewModifier { content in
            content.trackRUMTapAction(name: name)
        }
    }

    func privacyView<Content: View>(
        text: CatalogSwiftUI.TextPrivacyLevel?,
        image: CatalogSwiftUI.ImagePrivacyLevel?,
        touch: CatalogSwiftUI.TouchPrivacyLevel?,
        hide: Bool?,
        content: @escaping () -> Content
    ) -> AnyView {
        AnyView(
            SessionReplayPrivacyView(
                textAndInputPrivacy: .init(text),
                imagePrivacy: .init(image),
                touchPrivacy: .init(touch),
                hide: hide,
                content: content
            )
        )
    }
}

extension TextAndInputPrivacyLevel {
    fileprivate init?(_ text: CatalogSwiftUI.TextPrivacyLevel?) {
        guard let text else {
            return nil
        }

        switch text {
        case .maskSensitiveInputs:
            self = .maskSensitiveInputs
        case .maskAllInputs:
            self = .maskAllInputs
        case .maskAll:
            self = .maskAll
        }
    }
}

extension ImagePrivacyLevel {
    fileprivate init?(_ image: CatalogSwiftUI.ImagePrivacyLevel?) {
        guard let image else {
            return nil
        }

        switch image {
        case .maskNonBundledOnly:
            self = .maskNonBundledOnly
        case .maskAll:
            self = .maskAll
        case .maskNone:
            self = .maskNone
        }
    }
}

extension TouchPrivacyLevel {
    fileprivate init?(_ touch: CatalogSwiftUI.TouchPrivacyLevel?) {
        guard let touch else {
            return nil
        }

        switch touch {
        case .show:
            self = .show
        case .hide:
            self = .hide
        }
    }
}
