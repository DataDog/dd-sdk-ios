/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
import HTTPServerMock
@testable import Datadog

/// Shared server instance for all test cases.
private(set) var server: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional
/// Shared server session for all test cases.
private(set) var serverSession: ServerSession! // swiftlint:disable:this implicitly_unwrapped_optional

/// Base class providing mock server instrumentation.
class BenchmarkTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if server == nil { server = try! setUpMockServerConnection() }
        if serverSession == nil { serverSession = server.obtainUniqueRecordingSession() }
    }

    override func setUp() {
        super.setUp()
        Datadog.initialize(
            appContext: Datadog.AppContext(mainBundle: Bundle.main),
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "client-token", environment: "benchmarks")
                .set(logsEndpoint: .custom(url: serverSession.recordingURL.absoluteString))
                .build()
        )
    }

    override func tearDown() {
        try! Datadog.deinitializeOrThrow()
        super.tearDown()
    }

    // MARK: - `HTTPServerMock` connection

    private static func setUpMockServerConnection() throws -> ServerMock {
        let testsBundle = Bundle(for: BenchmarkTests.self)
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
