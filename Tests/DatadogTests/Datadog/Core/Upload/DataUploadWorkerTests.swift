/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadWorkerTests: XCTestCase {
    private let fileReadWriteQueue = DispatchQueue(label: "dd-tests-read-write", target: .global(qos: .utility))
    private let uploaderQueue = DispatchQueue(label: "dd-tests-uploader", target: .global(qos: .utility))

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItUploadsAllData() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = FilesOrchestrator(
            directory: temporaryDirectory,
            performance: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
            dateProvider: dateProvider
        )
        let writer = FileWriter(
            dataFormat: .mockWith(prefix: "[", suffix: "]"),
            orchestrator: orchestrator,
            queue: fileReadWriteQueue
        )
        let reader = FileReader(
            dataFormat: .mockWith(prefix: "[", suffix: "]"),
            orchestrator: orchestrator,
            queue: fileReadWriteQueue
        )
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.urlSession),
            httpHeaders: .mockAny()
        )

        // Write 3 files
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // Start logs uploader
        let uploadWorker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions(
                batteryStatus: BatteryStatusProviderMock.mockWith(
                    status: BatteryStatus(state: .full, level: 100, isLowPowerModeEnabled: false) // always upload
                ),
                networkConnectionInfo: NetworkConnectionInfoProviderMock(
                    networkConnectionInfo: NetworkConnectionInfo(
                        reachability: .yes, // always upload
                        availableInterfaces: [.wifi],
                        supportsIPv4: true,
                        supportsIPv6: true,
                        isExpensive: false,
                        isConstrained: false
                    )
                )
            ),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )

        let recordedRequests = server.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

        uploaderQueue.sync {} // wait until last "process upload" operation completes (to make sure "delete file" was requested)
        fileReadWriteQueue.sync {} // wait until last scheduled "delete file" operation completed

        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        _ = uploadWorker // keep the strong reference
    }
}
