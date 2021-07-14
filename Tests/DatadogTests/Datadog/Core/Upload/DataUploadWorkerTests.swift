/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadWorkerTests: XCTestCase {
    private let uploaderQueue = DispatchQueue(label: "dd-tests-uploader", target: .global(qos: .utility))

    lazy var dateProvider = RelativeDateProvider(advancingBySeconds: 1)
    lazy var orchestrator = FilesOrchestrator(
        directory: temporaryDirectory,
        performance: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
        dateProvider: dateProvider
    )
    lazy var writer = FileWriter(
        dataFormat: .mockWith(prefix: "[", suffix: "]"),
        orchestrator: orchestrator
    )
    lazy var reader = FileReader(
        dataFormat: .mockWith(prefix: "[", suffix: "]"),
        orchestrator: orchestrator
    )

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItUploadsAllData() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )

        // Then
        let recordedRequests = server.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

        worker.cancelSynchronously()

        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    func testWhenThereIsNoBatch_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.neverUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 0)
        waitForExpectations(timeout: 1, handler: nil)
        worker.cancelSynchronously()
    }

    func testWhenBatchFails_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 500)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 1, handler: nil)
        worker.cancelSynchronously()
    }

    func testWhenBatchSucceeds_thenIntervalDecreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is decreased")
        let mockDelay = MockDelay { command in
            if case .decrease = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 2, handler: nil)
        worker.cancelSynchronously()
    }

    func testWhenCancelled_itPerformsNoMoreUploads() {
        // Given
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.neverUpload(),
            delay: MockDelay(),
            featureName: .mockAny()
        )

        // When
        worker.cancelSynchronously()

        // Then
        writer.write(value: ["k1": "v1"])

        server.waitFor(requestsCompletion: 0)
    }

    func testItFlushesAllData() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        worker.flushSynchronously()

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        let recordedRequests = server.waitAndReturnRequests(count: 3)
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k1":"v1"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k2":"v2"}]"#.utf8Data })
        XCTAssertTrue(recordedRequests.contains { $0.httpBody == #"[{"k3":"v3"}]"#.utf8Data })

        worker.cancelSynchronously()
    }

    func testGivenDataToUpload_whenUploadFinishesWithSuccessStatusCode_thenDataIsDeleted() {
        let statusCode = (200...299).randomElement()!

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: statusCode)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        worker.cancelSynchronously()
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "When status code \(statusCode) is received, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesWithRedirectStatusCode_thenDataIsDeleted() {
        let statusCode = (300...399).randomElement()!

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: statusCode)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        worker.cancelSynchronously()
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "When status code \(statusCode) is received, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesWithClientErrorStatusCode_thenDataIsDeleted() {
        let statusCode = (400...499).randomElement()!

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: statusCode)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        worker.cancelSynchronously()
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "When status code \(statusCode) is received, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesWithClientTokenErrorStatusCode_thenDataIsDeleted() {
        let statusCode = 403

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: statusCode)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        worker.cancelSynchronously()
        XCTAssertEqual(try temporaryDirectory.files().count, 0, "When status code \(statusCode) is received, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesWithServerErrorStatusCode_thenDataIsPreserved() {
        let statusCode = (500...599).randomElement()!
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: statusCode)))
        let dataUploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            httpHeaders: .mockAny()
        )

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        worker.cancelSynchronously()
        XCTAssertEqual(try temporaryDirectory.files().count, 1, "When status code \(statusCode) is received, data should be preserved")
    }
}

struct MockDelay: Delay {
    enum Command {
        case increase, decrease
    }

    var callback: ((Command) -> Void)?
    let current: TimeInterval = 0.1

    mutating func decrease() {
        callback?(.decrease)
        callback = nil
    }
    mutating func increase() {
        callback?(.increase)
        callback = nil
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
