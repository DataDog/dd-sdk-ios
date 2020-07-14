/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class UIViewControllerAutoInstrumentation {
    static var instance: UIViewControllerAutoInstrumentation?

    let swizzler: UIViewControllerSwizzler

    convenience init?(with configuration: Datadog.Configuration) {
        if !configuration.rumEnabled || configuration.vcInstrumentationMode == .off {
            return nil
        }
        self.init(instrumentationMode: configuration.vcInstrumentationMode)
    }

    init?(instrumentationMode: Datadog.Configuration.ViewControllerInstrumentationMode) {
        do {
            self.swizzler = try UIViewControllerSwizzler(instrumentationMode: instrumentationMode)
        } catch {
            userLogger.warn("🔥 UIViewControllers won't be instrumented automatically: \(error)")
            developerLogger?.warn("🔥 UIViewController won't be instrumented automatically: \(error)")
            return nil
        }
    }

    func apply() {
        swizzler.swizzle()
    }
}
