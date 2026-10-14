/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal

@testable import DatadogSessionReplay
@testable import TestUtilities

class ResourcesWriterTests: XCTestCase {
    let resources: [EnrichedResource] = [.mockWith(identifier: "1"), .mockWith(identifier: "2")]
    var scopeMock: FeatureScopeMock! // swiftlint:disable:this implicitly_unwrapped_optional
    let dateProvider = DateProviderMock(now: Date(timeIntervalSince1970: 1_000))
    var availabilityStore: ResourceAvailabilityStore! // swiftlint:disable:this implicitly_unwrapped_optional
    var writer: ResourcesWriter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        scopeMock = FeatureScopeMock()
        availabilityStore = ResourceAvailabilityStore(scope: scopeMock, dateProvider: dateProvider)
        writer = ResourcesWriter(scope: scopeMock, availabilityStore: availabilityStore)
    }

    override func tearDown() {
        writer = nil
        availabilityStore = nil
        scopeMock = nil
    }

    func test_whenWritesResources_itWritesEachIdentifierOnce() {
        // When
        writer.write(resources: resources + resources)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources)
        XCTAssertTrue(scopeMock.dataStoreMock.storage.isEmpty)
    }

    func test_whenWriterIsRecreated_itWritesPreviouslyScheduledResources() {
        // Given
        writer.write(resources: resources)

        // When
        writer = ResourcesWriter(scope: scopeMock, availabilityStore: availabilityStore)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources + resources)
    }

    func test_whenConfirmationExpires_itWritesTheResource() {
        // Given
        let resource: EnrichedResource = .mockAny()
        availabilityStore.insert([resource.identifier], forApplicationID: resource.context.application.id)
        writer.write(resources: [resource])
        XCTAssertTrue(scopeMock.eventsWritten(ofType: EnrichedResource.self).isEmpty)

        // When
        dateProvider.now.addTimeInterval(30.days)
        writer.write(resources: [resource])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), [resource])
    }

    func test_whenApplicationsShareAnIdentifier_itDeduplicatesEachApplicationSeparately() {
        // Given
        let confirmedResource: EnrichedResource = .mockWith(identifier: "shared", context: .init("confirmed-app"))
        let unconfirmedResources: [EnrichedResource] = [
            .mockWith(identifier: "shared", context: .init("other-app")),
            .mockWith(identifier: "shared", context: .init("another-app"))
        ]
        availabilityStore.insert([confirmedResource.identifier], forApplicationID: confirmedResource.context.application.id)

        // When
        writer.write(resources: [confirmedResource] + unconfirmedResources)
        writer.write(resources: [confirmedResource] + unconfirmedResources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), unconfirmedResources)
    }

    func test_whenLegacyIdentifiersExist_itDiscardsThemAndWritesResources() throws {
        // Given
        let storeCreation = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
        let otherValue = Data("other-value".utf8)
        scopeMock.dataStoreMock.storage = [
            "known-resources": .value(try JSONEncoder().encode(resources.map(\.identifier)), 1),
            "store-creation": .value(storeCreation, 1),
            "other-key": .value(otherValue, 1)
        ]

        // When
        writer = ResourcesWriter(scope: scopeMock, availabilityStore: availabilityStore)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources)
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: "known-resources"))
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: "store-creation"))
        XCTAssertEqual(scopeMock.dataStoreMock.value(forKey: "other-key")?.data(expectedVersion: 1), otherValue)
    }
}
#endif
