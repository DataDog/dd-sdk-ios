/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggingFeatureTests: XCTestCase {
    func testInitialization() throws {
        let appContext: AppContext = .mockAny()
        Datadog.initialize(
            appContext: appContext,
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "abc")
                .build()
        )

        XCTAssertNotNil(LoggingFeature.instance)

        try Datadog.deinitializeOrThrow()
    }
}
