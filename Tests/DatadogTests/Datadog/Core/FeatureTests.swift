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

    func testGivenAnyFeatureStorage_whenWrittingDataAndChangingConsent_thenOnlyAuthorizedDataCanBeRead() {
        let consentProvider = ConsentProvider(initialConsent: randomConsent())

        // Given
        let storage = FeatureStorage(
            featureName: .mockAny(),
            dataFormat: DataFormat(prefix: "", suffix: "", separator: "#"),
            directories: temporaryFeatureDirectories,
            eventMapper: nil,
            commonDependencies: .mockWith(consentProvider: consentProvider)
        )

        // When
        (0..<100).forEach { _ in
            let currentConsent = consentProvider.currentValue
            let nextConsent = randomConsent(otherThan: currentConsent)

            let stringValue = "current consent: \(currentConsent), next consent: \(nextConsent)"
            storage.writer.write(value: stringValue)

            consentProvider.changeConsent(to: nextConsent)
        }

        // Then
        var dataAuthorizedForUpload: [Data] = []

        while true {
            if let nextBatch = storage.reader.readNextBatch() {
                dataAuthorizedForUpload.append(nextBatch.data)
                storage.reader.markBatchAsRead(nextBatch)
            } else {
                break
            }
        }

        let authorizedValues = dataAuthorizedForUpload.map { $0.utf8String }
        let expectedAuthorizedValues = [
            // Data collected with `.granted` consent is allowed no matter of the next consent
            "\"current consent: \(TrackingConsent.granted), next consent: \(TrackingConsent.pending)\"",
            "\"current consent: \(TrackingConsent.granted), next consent: \(TrackingConsent.notGranted)\"",
            // Data collected with `.pending` consent is allowed only if the next consent was `.granted`
            "\"current consent: \(TrackingConsent.pending), next consent: \(TrackingConsent.granted)\"",
        ]

        XCTAssertEqual(
            Set(authorizedValues),
            Set(expectedAuthorizedValues)
        )
    }

    // MARK: - Helpers

    /// Returns random consent value other than the given one.
    private func randomConsent(otherThan consent: TrackingConsent? = nil) -> TrackingConsent {
        while true {
            let randomConsent: TrackingConsent = [.granted, .pending, .notGranted].randomElement()!
            if randomConsent != consent {
                return randomConsent
            }
        }
    }
}
