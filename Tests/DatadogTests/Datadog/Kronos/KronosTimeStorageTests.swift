/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import XCTest
@testable import Datadog

class KronosTimeStoragePolicyTests: XCTestCase {
    func testInitWithStringGivesAppGroupType() {
        let group = KronosTimeStoragePolicy(appGroupID: "com.test.something.mygreatapp")
        if case KronosTimeStoragePolicy.appGroup(_) = group {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
    }

    func testInitWithNIlGivesStandardType() {
        let group = KronosTimeStoragePolicy(appGroupID: nil)
        if case KronosTimeStoragePolicy.standard = group {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
    }
}

class KronosTimeStorageTests: XCTestCase {
    func testStoringAndRetrievingTimeFreeze() {
        var storage = KronosTimeStorage(storagePolicy: .standard)
        let sampleFreeze = KronosTimeFreeze(offset: 5_000.32423)
        storage.stableTime = sampleFreeze

        let fromDefaults = storage.stableTime
        XCTAssertNotNil(fromDefaults)
        XCTAssertEqual(sampleFreeze.toDictionary(), fromDefaults!.toDictionary())
    }

    func testRetrievingTimeFreezeAfterReboot() {
        let sampleFreeze = KronosTimeFreeze(offset: 5_000.32423)
        var storedData = sampleFreeze.toDictionary()
        storedData["Uptime"] = storedData["Uptime"]! + 10

        let beforeRebootFreeze = KronosTimeFreeze(from: sampleFreeze.toDictionary())
        let afterRebootFreeze = KronosTimeFreeze(from: storedData)
        XCTAssertNil(afterRebootFreeze)
        XCTAssertNotNil(beforeRebootFreeze)
    }
}
