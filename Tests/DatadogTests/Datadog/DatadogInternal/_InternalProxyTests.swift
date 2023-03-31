/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class _InternalProxyTests: XCTestCase {
    func testWhenTelemetryIsSentThroughProxy_thenItForwardsToDDTelemetry() throws {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        // When
        let randomDebugMessage: String = .mockRandom()
        let randomErrorMessage: String = .mockRandom()
        Datadog._internal.telemetry.debug(id: .mockAny(), message: randomDebugMessage)
        Datadog._internal.telemetry.error(id: .mockAny(), message: randomErrorMessage, kind: .mockAny(), stack: .mockAny())

        // Then
        XCTAssertEqual(dd.telemetry.debugs.first, randomDebugMessage)
        XCTAssertEqual(dd.telemetry.errors.first?.message, randomErrorMessage)
    }

    func testWhenNewVersionIsSetInConfigurationProxy_thenItChangesAppVersionInCore() throws {
        // Given
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: .mockAny()
        )
        defer { Datadog.flushAndDeinitialize() }

        // When
        let randomVersion: String = .mockRandom()
        Datadog._internal.set(customVersion: randomVersion)

        // Then
        let core = try XCTUnwrap(defaultDatadogCore as? DatadogCore)
        XCTAssertEqual(core.applicationVersionPublisher.version, randomVersion)
    }
}
