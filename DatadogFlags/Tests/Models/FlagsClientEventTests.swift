/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogFlags

final class FlagsClientEventTests: XCTestCase {
    func testPublicInitializerDefaultsKeysToAbsent() {
        let event = FlagsClientEvent(type: .configurationChanged)

        XCTAssertEqual(event.type, .configurationChanged)
        XCTAssertNil(event.flagsChanged)
    }

    func testAbsentAndExplicitEmptyKeysAreDistinct() {
        let absent = FlagsClientEvent(type: .configurationChanged)
        let explicitAbsent = FlagsClientEvent(type: .configurationChanged, flagsChanged: nil)
        let empty = FlagsClientEvent(type: .configurationChanged, flagsChanged: [])

        XCTAssertEqual(absent, explicitAbsent)
        XCTAssertEqual(empty.flagsChanged, [])
        XCTAssertNotEqual(absent, empty)
    }

    func testKeysHaveIndependentValueSemantics() {
        var callerKeys = ["first", "second", "first"]
        let event = FlagsClientEvent(type: .configurationChanged, flagsChanged: callerKeys)
        callerKeys[0] = "changed"
        callerKeys.removeLast()
        var returnedKeys = event.flagsChanged
        returnedKeys?.append("another")

        XCTAssertEqual(event.flagsChanged, ["first", "second", "first"])
        XCTAssertEqual(callerKeys, ["changed", "second"])
        XCTAssertEqual(returnedKeys, ["first", "second", "first", "another"])
    }

    func testBridgedMutableKeysAreSnapshotted() {
        let callerKeys = NSMutableArray(array: ["first"])
        let event = FlagsClientEvent(type: .configurationChanged, flagsChanged: callerKeys as? [String])
        callerKeys.add("later")

        XCTAssertEqual(event.flagsChanged, ["first"])
    }

    func testConfigurationChangedMapsToSharedString() {
        XCTAssertEqual(FlagsClientEventType.configurationChanged.rawValue, "CONFIGURATION_CHANGED")
        XCTAssertEqual(FlagsClientEventType(rawValue: "CONFIGURATION_CHANGED"), .configurationChanged)
        for unsupported in ["READY", "ERROR", "STALE", "RECONCILING", "CONTEXT_CHANGED", "UNKNOWN"] {
            XCTAssertNil(FlagsClientEventType(rawValue: unsupported))
        }
    }
}
