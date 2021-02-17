/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMWithCrashContextIntegrationTests: XCTestCase {
    func testWhenCrashReporterIsRegistered_itUpdatesCrashContextWithLastRUMView() throws {
        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny()
        )

        // When
        Global.crashReporter = CrashReporter(
            crashReportingPlugin: CrashReportingPluginMock(),
            crashContextProvider: crashContextProvider,
            loggingOrRUMIntegration: CrashReportingIntegrationMock()
        )
        defer { Global.crashReporter = nil }

        // Then
        let rumWithCrashContextIntegration = try XCTUnwrap(RUMWithCrashContextIntegration())
        let randomRUMViewEvent: RUMEvent<RUMViewEvent> = .mockRandomWith(model: RUMViewEvent.mockRandom())
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)

        XCTAssertEqual(crashContextProvider.currentCrashContext.lastRUMViewEvent, randomRUMViewEvent)
    }

    func testWhenCrashReporterIsNotRegistered_itCannotBeInitialized() {
        // When
        XCTAssertNil(Global.crashReporter)

        // Then
        XCTAssertNil(RUMWithCrashContextIntegration())
    }
}
