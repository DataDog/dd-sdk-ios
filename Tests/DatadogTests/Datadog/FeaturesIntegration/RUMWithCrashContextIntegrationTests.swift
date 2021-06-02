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
        CrashReportingFeature.instance = .mockNoOp()
        defer { CrashReportingFeature.instance?.deinitialize() }

        // Then
        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration())
        let randomRUMViewEvent: RUMEvent<RUMViewEvent> = .mockRandomWith(model: RUMViewEvent.mockRandom())
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)

        XCTAssertEqual(CrashReportingFeature.instance?.rumViewEventProvider.currentValue, randomRUMViewEvent)
    }

    func testWhenCrashReportingIsNotEnabled_itCannotBeInitialized() {
        // When
        XCTAssertNil(CrashReportingFeature.instance)

        // Then
        XCTAssertNil(RUMWithCrashContextIntegration())
    }
}
