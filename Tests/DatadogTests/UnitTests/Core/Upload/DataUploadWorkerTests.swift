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

    func testItUploadsAllLogs() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: .mockWriteToNewFileEachTime(),
            readConditions: .mockReadAllFiles(),
            dateProvider: dateProvider
        )
        let writer = FileWriter(orchestrator: orchestrator, queue: fileReadWriteQueue, maxWriteSize: .max)
        let reader = FileReader(orchestrator: orchestrator, queue: fileReadWriteQueue)
        let requestsRecorder = RequestsRecorder()
        let dataUploader = DataUploader(
            url: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: 200, requestsRecorder: requestsRecorder),
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
            uploadConditions: .mockAlwaysPerformingUpload(),
            delay: .mockConstantDelay(of: 0.1)
        )

        Thread.sleep(forTimeInterval: 1) // 1 second is enough to send 3 logs with 0.1 second interval

        XCTAssertEqual(requestsRecorder.requestsSent.count, 3)
        XCTAssertTrue(requestsRecorder.containsRequestWith(body: #"[{"k1":"v1"}]"#.utf8Data))
        XCTAssertTrue(requestsRecorder.containsRequestWith(body: #"[{"k2":"v2"}]"#.utf8Data))
        XCTAssertTrue(requestsRecorder.containsRequestWith(body: #"[{"k3":"v3"}]"#.utf8Data))
        XCTAssertEqual(try temporaryDirectory.files().count, 0)

        _ = uploadWorker // keep the strong reference
    }
}
