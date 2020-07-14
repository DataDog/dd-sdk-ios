/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock
@testable import Datadog

struct ServerConnectionError: Error {
    let description: String
}

class DataUploadBenchmarkTests: XCTestCase {
    private(set) var server: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = try connectToServer()
    }

    override func tearDownWithError() throws {
        server = nil
        try super.tearDownWithError()
    }

    func testWhenUploadingDataToServer_memoryConsumptionIsConstant() {
        // TODO: RUMM-610 Add test
    }

    // MARK: - `HTTPServerMock` connection

    func connectToServer() throws -> ServerMock {
        let testsBundle = Bundle(for: DataUploadBenchmarkTests.self)
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
