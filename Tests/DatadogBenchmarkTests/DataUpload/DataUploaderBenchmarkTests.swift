/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock
@testable import Datadog

@available(iOS 13.0, *)
class DataUploaderBenchmarkTests: BenchmarkTests {
    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory.create()
    }

    override func tearDownWithError() throws {
        temporaryDirectory.delete()
        try super.tearDownWithError()
    }

    /// NOTE: In RUMM-610 we noticed that due to internal `NSCache` used by the `URLSession`
    /// requests memory was leaked after upload. This benchmark ensures that uploading data with
    /// `DataUploader` leaves no memory footprint (the memory peak after upload is less or equal `0kB`).
    func testUploadingDataToServer_leavesNoMemoryFootprint() throws {
        let dataUploader = DataUploader(
            urlProvider: mockUploadURLProvider(),
            httpClient: HTTPClient(),
            httpHeaders: HTTPHeaders(headers: [])
        )

        // `measure` runs 5 iterations
        measure(metrics: [XCTMemoryMetric()]) {
            // in each, 10 requests are done:
            (0..<10).forEach { _ in
                let data = Data(repeating: 0x41, count: 10 * 1_024 * 1_024)
                _ = dataUploader.upload(data: data)
            }
            // After all, the baseline asserts `0kB` or less grow in Physical Memory.
            // This makes sure that no request data is leaked (e.g. due to internal caching).
        }
    }

    private func mockUploadURLProvider() -> UploadURLProvider {
        return UploadURLProvider(
            urlWithClientToken: server.obtainUniqueRecordingSession().recordingURL,
            queryItemProviders: [.ddtags(tags: ["foo:bar"])]
        )
    }
}
