/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import ObjectiveC.runtime
@testable import Datadog

class HookedSessionTests: XCTestCase {
    func testDebug() {
        let session = URLSession.shared
        let originalClass = String(cString: object_getClassName(session))

        try? Swizzler.isaSwizzle(session)

        let newClass = String(cString: object_getClassName(session))

        XCTAssertNotEqual(originalClass, newClass)

        _ = session.dataTask(with: URL(string: "https://foo.bar")!)
        print("Done...")
    }

    func testIntegrity() {
        final class TestSessionDelegate: NSObject, URLSessionDelegate { }

        let config = URLSessionConfiguration.background(withIdentifier: "unitTestIdentifier")
        let delegate = TestSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        XCTAssertEqual(session.configuration.identifier, config.identifier)
        XCTAssertTrue(session.superclass is URLSession.Type)
        XCTAssertNotNil(session.delegate)
        XCTAssertEqual(session.delegate!.debugDescription, delegate.debugDescription)
    }
}
