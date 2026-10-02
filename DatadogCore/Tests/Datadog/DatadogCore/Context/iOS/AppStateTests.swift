/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(macOS)
import XCTest
import DatadogInternal
@testable import DatadogCore

@MainActor
class AppStateTests: XCTestCase {
    func testItBuildsAppStateFromUIApplicationState() {
        XCTAssertEqual(AppState(.active), .active)
        XCTAssertEqual(AppState(.inactive), .inactive)
        XCTAssertEqual(AppState(.background), .background)
    }
}
#endif
