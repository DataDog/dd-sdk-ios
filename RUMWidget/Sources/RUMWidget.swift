/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import DatadogCore
import UIKit

@available(iOS 15.0, *)
public enum RUMWidget {

    private static var buttonHostingController: RUMWidgetHostingController?

    public static func enable(
        with configuration: Datadog.Configuration,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
            consolePrint("\(error)", .error)
       }
    }

    internal static func enableOrThrow(
        with configuration: Datadog.Configuration,
        in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore),
        Self.buttonHostingController == nil,
        let view = Self.superView() else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `RUMWidget.enable(with:)`."
            )
        }

        // Register RUMWidget feature:
        let feature = try RUMWidgetFeature(in: core, configuration: configuration)
        //        try core.register(feature: rum)

        let buttonHostingController = RUMWidgetHostingController(feature: feature)
        buttonHostingController.setup(superView: view)
        self.buttonHostingController = buttonHostingController
    }

    public static func bringToFront(superview: UIView? = nil) {

        guard let superView = superview ?? self.superView(), let buttonHostingController else { return }

        superView.bringSubviewToFront(buttonHostingController.view)
    }

    private static func superView() -> UIView? {

        if var topController = UIApplication.shared.windows.first?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }

            return topController.view
        }

        return nil
    }
}
