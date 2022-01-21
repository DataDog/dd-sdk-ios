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
        CrashReportingFeature.instance = crashReporting
        defer { CrashReportingFeature.instance?.deinitialize() }

        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration())

        // Then
        let randomRUMViewEvent: RUMViewEvent = .mockRandom()
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)
        XCTAssertEqual(crashReporting.rumViewEventProvider.currentValue, randomRUMViewEvent)

        rumWithCrashContextIntegration.update(lastRUMViewEvent: nil)
        XCTAssertNil(crashReporting.rumViewEventProvider.currentValue)
    }

    func testWhenCrashReportingIsEnabled_itUpdatesCrashContextWithRUMSessionState() throws {
        // When
        CrashReportingFeature.instance = .mockNoOp()
        defer { CrashReportingFeature.instance?.deinitialize() }

        // Then
        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration())
        let randomRUMSessionState: RUMSessionState = .mockRandom()
        rumWithCrashContextIntegration.update(lastRUMSessionState: randomRUMSessionState)

        XCTAssertEqual(CrashReportingFeature.instance?.rumSessionStateProvider.currentValue, randomRUMSessionState)
    }

    func testWhenCrashReportingIsNotEnabled_itCannotBeInitialized() {
        // When
        XCTAssertNil(CrashReportingFeature.instance)

        // Then
        XCTAssertNil(RUMWithCrashContextIntegration())
    }
}
