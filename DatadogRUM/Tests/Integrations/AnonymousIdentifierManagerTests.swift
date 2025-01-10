/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class AnonymousIdentifierManagerTests: XCTestCase {
    private var anonymousIdentifierManager: AnonymousIdentifierManager! // swiftlint:disable:this implicitly_unwrapped_optional
    private var featureScopeMock: FeatureScopeMock!
    private var uuidGeneratorMock: RUMUUIDGeneratorMock!

    override func setUp() {
        uuidGeneratorMock = RUMUUIDGeneratorMock(uuid: .mockRandom())
        featureScopeMock = FeatureScopeMock()
        anonymousIdentifierManager = AnonymousIdentifierManager(
            featureScope: featureScopeMock,
            uuidGenerator: uuidGeneratorMock
        )
    }

    override func tearDown() {
        anonymousIdentifierManager = nil
    }

    func testWhenShouldTrack_itGeneratesAnonymousID() {
        anonymousIdentifierManager.manageAnonymousId(shouldTrack: true)

        XCTAssertNotNil(featureScopeMock.anonymousId)
    }

    func testWhenShouldNotTrack_itClearsAnonymousID() {
        anonymousIdentifierManager.manageAnonymousId(shouldTrack: false)
        XCTAssertNil(featureScopeMock.anonymousId)

        featureScopeMock.set(anonymousId: "test")

        anonymousIdentifierManager.manageAnonymousId(shouldTrack: false)
        XCTAssertNil(featureScopeMock.anonymousId)
    }

    func testWhenCalledMultipleTimes_itGeneratesTheSameAnonymousID() {
        let uuid1 = RUMUUID.mockRandom()
        uuidGeneratorMock.uuid = uuid1
        anonymousIdentifierManager.manageAnonymousId(shouldTrack: true)
        XCTAssertEqual(featureScopeMock.anonymousId, uuid1.toRUMDataFormat)

        let uuid2 = RUMUUID.mockRandom()
        uuidGeneratorMock.uuid = uuid2
        anonymousIdentifierManager.manageAnonymousId(shouldTrack: true)
        XCTAssertEqual(featureScopeMock.anonymousId, uuid1.toRUMDataFormat)
    }
}
