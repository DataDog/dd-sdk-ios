/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock
import Datadog

struct ServerConnectionError: Error {
    let description: String
}

/// Base class providing mock server instrumentation and SDK initialization.
class BenchmarkTests: XCTestCase {
    /// Python server instance.
    private(set) var server: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = try connectToServer()
        initializeSDKIfNotInitialized()
    }

    override func tearDownWithError() throws {
        server = nil

        try super.tearDownWithError()
    }

    // MARK: - SDK Initialization

    private static var isSDKInitialized = false

    private func initializeSDKIfNotInitialized() {
        if BenchmarkTests.isSDKInitialized {
            return
        }

        BenchmarkTests.isSDKInitialized = true

        let anyURL = server.obtainUniqueRecordingSession().recordingURL

        Datadog.initialize(
            appContext: .init(),
            configuration: Datadog.Configuration
                .builderUsing(rumApplicationID: "rum-123", clientToken: "rum-abc", environment: "benchmarks")
                .set(logsEndpoint: .custom(url: anyURL.absoluteString))
                .set(tracesEndpoint: .custom(url: anyURL.absoluteString))
                .set(rumEndpoint: .custom(url: anyURL.absoluteString))
                .build()
        )

        Global.rum = RUMMonitor.initialize()
        Global.sharedTracer = Tracer.initialize(configuration: .init())
    }

    // MARK: - `HTTPServerMock` connection

    private func connectToServer() throws -> ServerMock {
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
