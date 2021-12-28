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

class TimeStorageTests: XCTestCase {
    func testStoringAndRetrievingTimeFreeze() {
        var storage = KronosTimeStorage(storagePolicy: .standard)
        let sampleFreeze = KronosTimeFreeze(offset: 5_000.324_23)
        storage.stableTime = sampleFreeze

        let fromDefaults = storage.stableTime
        XCTAssertNotNil(fromDefaults)
        XCTAssertEqual(sampleFreeze.toDictionary(), fromDefaults!.toDictionary())
    }

    func testRetrievingTimeFreezeAfterReboot() {
        let sampleFreeze = KronosTimeFreeze(offset: 5_000.324_23)
        var storedData = sampleFreeze.toDictionary()
        storedData["Uptime"] = storedData["Uptime"]! + 10

        let beforeRebootFreeze = KronosTimeFreeze(from: sampleFreeze.toDictionary())
        let afterRebootFreeze = KronosTimeFreeze(from: storedData)
        XCTAssertNil(afterRebootFreeze)
        XCTAssertNotNil(beforeRebootFreeze)
    }
}
