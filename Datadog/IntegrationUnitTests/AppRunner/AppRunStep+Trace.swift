/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogTrace

extension AppRunStep {
    /// Convenience helper for initializing the SDK and enabling the Trace feature in one step.
    static func enableTrace(
        after dt: TimeInterval = 0,
        sdkSetup: AppRunner.SDKSetup? = nil,
        traceSetup: AppRunner.TraceSetup? = nil
    ) -> AppRunStep {
        return AppRunStep({ app in
            AppRunStep.advanceTime(by: dt).perform(app)
            AppRunStep.initializeSDK(sdkSetup: sdkSetup).perform(app)
            AppRunStep.enableTrace(traceSetup: traceSetup).perform(app)
        })
    }

    /// Enables the Trace feature. Assumes the SDK has been initialized via `initializeSDK`.
    static func enableTrace(traceSetup: AppRunner.TraceSetup? = nil) -> AppRunStep {
        return AppRunStep({ app in
            app.enableTrace { config in
                traceSetup?(&config)
            }
        })
    }
}
