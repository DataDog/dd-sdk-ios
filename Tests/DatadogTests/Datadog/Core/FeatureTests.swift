/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FeatureStorageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    func testWhenWrittingDataAndChangingConsent_thenOnlyAuthorizedDataCanBeRead() {
        let consentProvider = ConsentProvider(initialConsent: .mockRandom())

        // Given
        let storage = FeatureStorage(
            featureName: .mockAny(),
            dataFormat: DataFormat(prefix: "", suffix: "", separator: "#"),
            directories: temporaryFeatureDirectories,
            commonDependencies: .mockWith(consentProvider: consentProvider)
        )

        // When
        (0..<100).forEach { _ in
            let currentConsent = consentProvider.currentValue
            let nextConsent: TrackingConsent = .mockRandom(otherThan: currentConsent)

            // We write array because prior to iOS 13 the top-level element passed to JSON encoder must be array or object
            let data = ["current consent: \(currentConsent), next consent: \(nextConsent)"]
            storage.writer.write(value: data)

            consentProvider.changeConsent(to: nextConsent)
        }

        // Then
        let authorizedValues = readAllAuthorizedDataWritten(to: storage, limit: 100)
            .map { $0.utf8String }

        let expectedAuthorizedValues = [
            // Data collected with `.granted` consent is allowed no matter of the next consent
            "[\"current consent: \(TrackingConsent.granted), next consent: \(TrackingConsent.pending)\"]",
            "[\"current consent: \(TrackingConsent.granted), next consent: \(TrackingConsent.notGranted)\"]",
            // Data collected with `.pending` consent is allowed only if the next consent was `.granted`
            "[\"current consent: \(TrackingConsent.pending), next consent: \(TrackingConsent.granted)\"]",
        ]

        XCTAssertEqual(
            Set(authorizedValues),
            Set(expectedAuthorizedValues)
        )
    }

    func testWhenArbitraryWriterIsUsedInParallelWithRegularWriter_thenAllDataIsWrittenSafely() {
        // Given
        let storage = FeatureStorage(
            featureName: .mockAny(),
            dataFormat: DataFormat(prefix: "", suffix: "", separator: "#"),
            directories: temporaryFeatureDirectories,
            commonDependencies: .mockWith(consentProvider: .init(initialConsent: .granted))
        )

        // When
        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                // We write arrays because prior to iOS 13 the top-level element passed to JSON encoder must be array or object
                { storage.writer.write(value: ["regular write"]) },
                { storage.arbitraryAuthorizedWriter.write(value: ["arbitrary write"]) }
            ],
            iterations: 25
        )
        // swiftlint:enable opening_brace

        // Then
        let dataWritten = readAllAuthorizedDataWritten(to: storage, limit: 50)
            .map { $0.utf8String }
        XCTAssertEqual(dataWritten.filter { $0 == "[\"regular write\"]" }.count, 25)
        XCTAssertEqual(dataWritten.filter { $0 == "[\"arbitrary write\"]" }.count, 25)
    }

    // MARK: - Helpers

    private func readAllAuthorizedDataWritten(
        to storage: FeatureStorage,
        limit: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Data] {
        var dataAuthorizedForUpload: [Data] = []

        (0..<limit).forEach { _ in
            if let nextBatch = storage.reader.readNextBatch() {
                dataAuthorizedForUpload.append(nextBatch.data)
                storage.reader.markBatchAsRead(nextBatch)
            }
        }

        return dataAuthorizedForUpload
    }
}
