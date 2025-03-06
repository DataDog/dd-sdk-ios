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
    // swiftlint:disable implicitly_unwrapped_optional
    private var anonymousIdentifierManager: AnonymousIdentifierManager!
    private var featureScopeMock: FeatureScopeMock!
    private var uuidGeneratorMock: RUMUUIDGeneratorMock!
    // swiftlint:enable implicitly_unwrapped_optional

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

    func testWhenShouldTrack_itGeneratesAnonymousIdentifier() {
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: true)

        XCTAssertNotNil(featureScopeMock.anonymousId)
    }

    func testWhenShouldNotTrack_itClearsAnonymousIdentifier() {
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: false)
        XCTAssertNil(featureScopeMock.anonymousId)

        featureScopeMock.set(anonymousId: "test")

        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: false)
        XCTAssertNil(featureScopeMock.anonymousId)
    }

    func testWhenCalledMultipleTimes_itGeneratesTheSameAnonymousIdentifier() {
        let uuid1 = RUMUUID.mockRandom()
        uuidGeneratorMock.uuid = uuid1
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: true)
        XCTAssertEqual(featureScopeMock.anonymousId, uuid1.toRUMDataFormat)

        let uuid2 = RUMUUID.mockRandom()
        uuidGeneratorMock.uuid = uuid2
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: true)
        XCTAssertEqual(featureScopeMock.anonymousId, uuid1.toRUMDataFormat)
    }
}
