/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

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
        XCTAssertEqual(dd.telemetry.messages.count, 2)

        guard case .debug(_, let receivedMessage, _) = dd.telemetry.messages.first else {
            return XCTFail("A debug should be send to `DD.telemetry`.")
        }
        XCTAssertEqual(receivedMessage, randomDebugMessage)

        guard case .error(_, let receivedMessage, _, _) = dd.telemetry.messages.last else {
            return XCTFail("An error should be send to `DD.telemetry`.")
        }
        XCTAssertEqual(receivedMessage, randomErrorMessage)
    }

    func testWhenNewVersionIsSetInConfigurationProxy_thenItChangesAppVersionInCore() throws {
        // Given
        Datadog.initialize(
            with: .mockAny(),
            trackingConsent: .mockRandom()
        )
        defer { Datadog.flushAndDeinitialize() }

        // When
        let randomVersion: String = .mockRandom()
        Datadog._internal.set(customVersion: randomVersion)

        // Then
        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)
        XCTAssertEqual(core.applicationVersionPublisher.version, randomVersion)
    }
}
