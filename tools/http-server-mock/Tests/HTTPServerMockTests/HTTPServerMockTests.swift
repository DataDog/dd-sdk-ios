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
        guard let serverProcess = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        // Given
        let server = ServerMock(serverProcess: serverProcess)
        let session = server.obtainUniqueRecordingSession()

        var request1 = URLRequest(url: session.recordingURL.appendingPathComponent("/resource/1"))
        request1.httpMethod = "POST"
        request1.httpBody = "1st request body".data(using: .utf8)!
        request1.setValue("Value1", forHTTPHeaderField: "Header1")
        request1.setValue("multipart/form-data; boundary=00000000-0000-0000-0000-000000000000", forHTTPHeaderField: "Content-Type")

        var request2 = URLRequest(url: session.recordingURL.appendingPathComponent("/resource/2"))
        request2.httpMethod = "POST"
        request2.httpBody = "2nd request body".data(using: .utf8)!
        request2.setValue("Value2", forHTTPHeaderField: "Header2")

        // When
        sendSynchronously(request: request1)
        sendSynchronously(request: request2)

        // Then
        let recordedRequests = try session.getRecordedRequests()

        XCTAssertEqual(recordedRequests.count, 2)
        XCTAssertTrue(recordedRequests[0].path.hasSuffix("/resource/1"))
        XCTAssertEqual(recordedRequests[0].httpBody, "1st request body".data(using: .utf8)!)
        XCTAssertEqual(recordedRequests[0].httpHeaders["Header1"], "Value1")
        XCTAssertEqual(recordedRequests[0].httpHeaders["Content-Type"], "multipart/form-data; boundary=00000000-0000-0000-0000-000000000000")

        XCTAssertTrue(recordedRequests[1].path.hasSuffix("/resource/2"))
        XCTAssertEqual(recordedRequests[1].httpBody, "2nd request body".data(using: .utf8)!)
        XCTAssertEqual(recordedRequests[1].httpHeaders["Header2"], "Value2")
    }

    func testItPullsRecordedRequests() throws {
        let runner = ServerProcessRunner(serverURL: URL(string: "http://127.0.0.1:8000")!)
        guard let serverProcess = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        // Given
        let server = ServerMock(serverProcess: serverProcess)
        let session = server.obtainUniqueRecordingSession()

        var request1 = URLRequest(url: session.recordingURL.appendingPathComponent("/resource/1"))
        request1.httpMethod = "POST"
        request1.httpBody = "1st request body".data(using: .utf8)!
        request1.setValue("Value1", forHTTPHeaderField: "Header1")

        var request2 = URLRequest(url: session.recordingURL.appendingPathComponent("/resource/2"))
        request2.httpMethod = "POST"
        request2.httpBody = "2nd request body".data(using: .utf8)!
        request2.setValue("Value2", forHTTPHeaderField: "Header2")

        // When
        let initialTime = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.5)
            sendAsynchronously(request: request1)
            Thread.sleep(forTimeInterval: 0.5)
            sendAsynchronously(request: request2)
        }
        let timeoutTime: TimeInterval = 2

        // Then
        let recordedRequests = try session.pullRecordedRequests(timeout: timeoutTime) { requests in
            requests.count == 2
        }
        XCTAssertLessThan(Date(), initialTime.addingTimeInterval(timeoutTime))
        XCTAssertEqual(recordedRequests.count, 2)
        XCTAssertTrue(recordedRequests[0].path.hasSuffix("/resource/1"))
        XCTAssertEqual(recordedRequests[0].httpBody, "1st request body".data(using: .utf8)!)
        XCTAssertEqual(recordedRequests[0].httpHeaders["Header1"], "Value1")

        XCTAssertTrue(recordedRequests[1].path.hasSuffix("/resource/2"))
        XCTAssertEqual(recordedRequests[1].httpBody, "2nd request body".data(using: .utf8)!)
        XCTAssertEqual(recordedRequests[1].httpHeaders["Header2"], "Value2")
    }

    func testWhenPullingRecordedRequestExceedsTimeout_itThrowsAnError() throws {
        let runner = ServerProcessRunner(serverURL: URL(string: "http://127.0.0.1:8000")!)
        guard let serverProcess = runner.waitUntilServerIsReachable() else {
            XCTFail("Failed to connect with the server.")
            return
        }

        let server = ServerMock(serverProcess: serverProcess)
        let session = server.obtainUniqueRecordingSession()

        XCTAssertThrowsError(
            try session.pullRecordedRequests(timeout: 1) { $0.count == 1 }
        ) { error in
            let description = (error as? Exception)?.description ?? ""
            XCTAssertTrue(
                description.hasPrefix("Exceeded 1.0s timeout with pulling 0 requests and not meeting the `condition()`."),
                "It must include expected description, got '\(description)' instead"
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

private func sendSynchronously(request: URLRequest) {
    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { _, _, error in
        XCTAssertNil(error)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 1)

    task.resume()
}

private func sendAsynchronously(request: URLRequest) {
    let task = URLSession.shared.dataTask(with: request) { _, _, error in
        XCTAssertNil(error)
    }
    task.resume()
}
