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

    lazy var dateProvider = RelativeDateProvider(advancingBySeconds: 1)
    lazy var orchestrator = FilesOrchestrator(
        directory: temporaryDirectory,
        performance: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
        dateProvider: dateProvider
    )
    lazy var writer = FileWriter(
        dataFormat: .mockWith(prefix: "[", suffix: "]"),
        orchestrator: orchestrator,
        queue: fileReadWriteQueue
    )
    lazy var reader = FileReader(
        dataFormat: .mockWith(prefix: "[", suffix: "]"),
        orchestrator: orchestrator,
        queue: fileReadWriteQueue
    )

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItUploadsAllData() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        // Write 3 files
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])
        // Start logs uploader
        try withExtendedLifetime(
            DataUploadWorker(
                queue: uploaderQueue,
                fileReader: reader,
                dataUploader: dataUploader,
                uploadConditions: DataUploadConditions.alwaysUpload(),
                delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
                featureName: .mockAny()
            )
        ) {
            let recordedRequests = server.waitAndReturnRequests(count: 3)
            XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
            XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
            XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

            uploaderQueue.sync {} // wait until last "process upload" operation completes (to make sure "delete file" was requested)
            fileReadWriteQueue.sync {} // wait until last scheduled "delete file" operation completed

            XCTAssertEqual(try temporaryDirectory.files().count, 0)
        }
    }

    // swiftlint:disable multiline_arguments_brackets
    func testWhenThereIsNoBatch_thenIntervalIncreases() throws {
        let expectation = XCTestExpectation(description: "high expectation")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                expectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        // Start logs uploader
        withExtendedLifetime([
            ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200))),
            DataUploadWorker(
                queue: uploaderQueue,
                fileReader: reader,
                dataUploader: dataUploader,
                uploadConditions: DataUploadConditions.neverUpload(),
                delay: mockDelay,
                featureName: .mockAny()
            )
        ]) {
            self.wait(for: [expectation], timeout: (mockDelay.current + 0.1) * 1.5)
        }
    }

    func testWhenBatchFails_thenIntervalIncreases() throws {
        let expectation = XCTestExpectation(description: "high expectation")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                expectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        // Write some content
        writer.write(value: ["k1": "v1"])
        // Start logs uploader
        withExtendedLifetime([
            ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 500))),
            DataUploadWorker(
                queue: uploaderQueue,
                fileReader: reader,
                dataUploader: dataUploader,
                uploadConditions: DataUploadConditions.alwaysUpload(),
                delay: mockDelay,
                featureName: .mockAny()
            )
        ]) {
            self.wait(for: [expectation], timeout: 1.5)
        }
    }

    func testWhenBatchSucceeds_thenIntervalDecreases() throws {
        let expectation = XCTestExpectation(description: "low expectation")
        let mockDelay = MockDelay { command in
            if case .decrease = command {
                expectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        // Write some content
        writer.write(value: ["k1": "v1"])
        // Start logs uploader
        withExtendedLifetime([
            ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200))),
            DataUploadWorker(
                queue: uploaderQueue,
                fileReader: reader,
                dataUploader: dataUploader,
                uploadConditions: DataUploadConditions.alwaysUpload(),
                delay: mockDelay,
                featureName: .mockAny()
            )
        ]) {
            self.wait(for: [expectation], timeout: 1.5)
        }
    }
    // swiftlint:enable multiline_arguments_brackets
}

struct MockDelay: Delay {
    enum Command {
        case increase, decrease
    }
    let callback: (Command) -> Void
    // NOTE: RUMM-737 private only doesn't compile due to "private initializer is inaccessible", probably a bug in Swift
    private(set) var didReceiveCommand = false

    let current: TimeInterval = 0

    mutating func decrease() {
        if didReceiveCommand {
            return
        }
        didReceiveCommand = true
        callback(.decrease)
    }
    mutating func increase() {
        if didReceiveCommand {
            return
        }
        didReceiveCommand = true
        callback(.increase)
    }
}

private extension DataUploadConditions {
    static func alwaysUpload() -> DataUploadConditions {
        return DataUploadConditions(
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
        )
    }

    static func neverUpload() -> DataUploadConditions {
        return DataUploadConditions(
            batteryStatus: BatteryStatusProviderMock.mockWith(
                status: BatteryStatus(state: .unplugged, level: 0, isLowPowerModeEnabled: true) // never upload
            ),
            networkConnectionInfo: NetworkConnectionInfoProviderMock(
                networkConnectionInfo: NetworkConnectionInfo(
                    reachability: .no, // never upload
                    availableInterfaces: [.cellular],
                    supportsIPv4: true,
                    supportsIPv6: false,
                    isExpensive: true,
                    isConstrained: true
                )
            )
        )
    }
}
