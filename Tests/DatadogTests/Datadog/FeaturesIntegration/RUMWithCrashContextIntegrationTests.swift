/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMWithCrashContextIntegrationTests: XCTestCase {
    func testWhenCrashReportingIsEnabled_itUpdatesCrashContextWithLastRUMView() throws {
        // When
        let crashReporting: CrashReportingFeature = .mockNoOp()

        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration(crashReporting: crashReporting))

        // Then
        let randomRUMViewEvent: RUMViewEvent = .mockRandom()
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)
        XCTAssertEqual(crashReporting.rumViewEventProvider.currentValue, randomRUMViewEvent)

        rumWithCrashContextIntegration.update(lastRUMViewEvent: nil)
        XCTAssertNil(crashReporting.rumViewEventProvider.currentValue)
    }

    func testWhenCrashReportingIsEnabled_itUpdatesCrashContextWithRUMSessionState() throws {
        // When
        let crashReporting: CrashReportingFeature = .mockNoOp()

        // Then
        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration(crashReporting: crashReporting))
        let randomRUMSessionState: RUMSessionState = .mockRandom()
        rumWithCrashContextIntegration.update(lastRUMSessionState: randomRUMSessionState)

        XCTAssertEqual(crashReporting.rumSessionStateProvider.currentValue, randomRUMSessionState)
    }
}
