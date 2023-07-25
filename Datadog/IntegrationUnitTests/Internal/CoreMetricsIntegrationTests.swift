/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogLogs
@testable import DatadogTrace
#if !os(tvOS)
@testable import DatadogSessionReplay
#endif

class CoreMetricsIntegrationTests: XCTestCase {
    func testResolvingTrackValueFromFeatureName() {
        XCTAssertEqual(BatchMetric.trackValue(for: RUMFeature.name), "rum")
        XCTAssertEqual(BatchMetric.trackValue(for: TraceFeature.name), "trace")
        XCTAssertEqual(BatchMetric.trackValue(for: LogsFeature.name), "logs")
        #if !os(tvOS)
        XCTAssertEqual(BatchMetric.trackValue(for: SessionReplayFeature.name), "sr")
        #endif
    }
}
