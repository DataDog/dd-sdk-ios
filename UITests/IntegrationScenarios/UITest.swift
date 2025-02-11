/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import HTTPServerMock

struct ServerConnectionError: Error {
    let description: String
}

/// Base class providing mock server instrumentation.
class UITests: XCTestCase {
    /// Python server instance.
    private(set) var server: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional
    /// Timeout for requesting data from Python server.
    let dataDeliveryTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = try connectToServer()
    }

    override func tearDownWithError() throws {
        server = nil
        try super.tearDownWithError()
    }

    // MARK: - `HTTPServerMock` connection

    private func connectToServer() throws -> ServerMock {
        let testsBundle = Bundle(for: UITests.self)
        guard let serverAddress = testsBundle.object(forInfoDictionaryKey: "MockServerAddress") as? String else {
            throw ServerConnectionError(description: "Cannot obtain `MockServerAddress` from `Info.plist`")
        }

        guard let serverURL = URL(string: "http://\(serverAddress)") else {
            throw ServerConnectionError(description: "`MockServerAddress` obtained from `Info.plist` is invalid.")
        }

        let serverProcessRunner = ServerProcessRunner(serverURL: serverURL)
        guard let serverProcess = serverProcessRunner.waitUntilServerIsReachable() else {
            throw ServerConnectionError(description: "Cannot connect to server. Is server running properly on \(serverURL.absoluteString)?")
        }

        print("🌍 Connected to mock server on \(serverURL.absoluteString)")

        let connectedServer = ServerMock(serverProcess: serverProcess)
        return connectedServer
    }
}
