/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import HTTPServerMock

final class HTTPServerMockTests: XCTestCase {
    #if os(macOS)
    private var process: Process! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        self.process = Process()
        self.process.launchPath = "/usr/bin/python3"
        self.process.arguments = [serverPythonScriptPath(), "--prefer-localhost"]
        self.process.launch()
    }

    override func tearDown() {
        self.process.terminate()
        super.tearDown()
    }
    #endif

    func testItReturnsRecordedRequests() throws {
        let runner = ServerProcessRunner(serverURL: URL(string: "http://127.0.0.1:8000")!)
        guard let serverProces = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        let server = ServerMock(serverProcess: serverProces)
        let session = server.obtainUniqueRecordingSession()

        sendPOSTRequestSynchronouslyTo(
            url: session.recordingURL.appendingPathComponent("/resource/1"),
            body: "1st request body".data(using: .utf8)!
        )
        sendPOSTRequestSynchronouslyTo(
            url: session.recordingURL.appendingPathComponent("/resource/2"),
            body: "2nd request body".data(using: .utf8)!
        )

        let recordedRequests = try session.getRecordedRequests()

        XCTAssertEqual(recordedRequests.count, 2)
        XCTAssertTrue(recordedRequests[0].path.hasSuffix("/resource/1"))
        XCTAssertEqual(recordedRequests[0].httpBody, "1st request body".data(using: .utf8)!)
        XCTAssertTrue(recordedRequests[1].path.hasSuffix("/resource/2"))
        XCTAssertEqual(recordedRequests[1].httpBody, "2nd request body".data(using: .utf8)!)
    }

    func testItPullsRecordedRequests() throws {
        let runner = ServerProcessRunner(serverURL: URL(string: "http://127.0.0.1:8000")!)
        guard let serverProces = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        let server = ServerMock(serverProcess: serverProces)
        let session = server.obtainUniqueRecordingSession()

        let initialTime = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.5)
            sendPOSTRequestAsynchronouslyTo(
                url: session.recordingURL.appendingPathComponent("/resource/1"),
                body: "1st request body".data(using: .utf8)!
            )
            Thread.sleep(forTimeInterval: 0.5)
            sendPOSTRequestAsynchronouslyTo(
                url: session.recordingURL.appendingPathComponent("/resource/2"),
                body: "2nd request body".data(using: .utf8)!
            )
        }
        let timeoutTime: TimeInterval = 2
        let recordedRequests = try session.pullRecordedRequests(timeout: timeoutTime) { requests in
            requests.count == 2
        }
        XCTAssertLessThan(Date(), initialTime.addingTimeInterval(timeoutTime))
        XCTAssertEqual(recordedRequests.count, 2)
        XCTAssertTrue(recordedRequests[0].path.hasSuffix("/resource/1"))
        XCTAssertEqual(recordedRequests[0].httpBody, "1st request body".data(using: .utf8)!)
        XCTAssertTrue(recordedRequests[1].path.hasSuffix("/resource/2"))
        XCTAssertEqual(recordedRequests[1].httpBody, "2nd request body".data(using: .utf8)!)
    }

    func testWhenPullingRecordedRequestExceedsTimeout_itThrowsAnError() throws {
        let runner = ServerProcessRunner(serverURL: URL(string: "http://127.0.0.1:8000")!)
        guard let serverProces = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        let server = ServerMock(serverProcess: serverProces)
        let session = server.obtainUniqueRecordingSession()

        XCTAssertThrowsError(
            try session.pullRecordedRequests(timeout: 1) { $0.count == 1 }
        ) { error in
            XCTAssertEqual(
                (error as? Exception)?.description,
                "Exceeded 1.0s timeout with pulling 0 requests and not meeting the `condition()`."
            )
        }
    }
}

// MARK: - Helpers

/// Resolves the url to the Python script starting the server.
private func serverPythonScriptPath() -> String {
    return resolveSwiftPackageFolder().path + "/python/start_mock_server.py"
}

/// Resolves the url to the folder containing `Package.swift`
private func resolveSwiftPackageFolder() -> URL {
    var currentFolder = URL(fileURLWithPath: #file).deletingLastPathComponent()

    while currentFolder.pathComponents.count > 0 {
        if FileManager.default.fileExists(atPath: currentFolder.appendingPathComponent("Package.swift").path) {
            return currentFolder
        } else {
            currentFolder.deleteLastPathComponent()
        }
    }

    fatalError("Cannot resolve the URL to folder containing `Package.swift`.")
}

private func sendPOSTRequestSynchronouslyTo(url: URL, body: Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body

    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { _, _, error in
        XCTAssertNil(error)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 1)

    task.resume()
}

private func sendPOSTRequestAsynchronouslyTo(url: URL, body: Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body

    let task = URLSession.shared.dataTask(with: request) { _, _, error in
        XCTAssertNil(error)
    }
    task.resume()
}
