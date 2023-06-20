/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import HTTPServerMock
import Datadog
import DatadogLogs
import DatadogTrace
import DatadogRUM

struct ServerConnectionError: Error {
    let description: String
}

/// Base class providing mock server instrumentation and SDK initialization.
class BenchmarkTests: XCTestCase {
    /// Python server instance.
    var server: ServerMock { BenchmarkTests.connectedServer! }

    override class func setUp() {
        super.setUp()
        do {
            try connectToServerIfNotConnected()
        } catch let error {
            fatalError("Failed to connect to Python server: \(error)")
        }
        initializeSDKIfNotInitialized()
    }

    // MARK: - SDK Initialization

    private static var isSDKInitialized = false

    private static func initializeSDKIfNotInitialized() {
        if BenchmarkTests.isSDKInitialized {
            return
        }

        BenchmarkTests.isSDKInitialized = true

        let anyURL = connectedServer!.obtainUniqueRecordingSession().recordingURL

        Datadog.initialize(
            appContext: .init(),
            trackingConsent: .granted,
            configuration: Datadog.Configuration
                .builderUsing(rumApplicationID: "rum-123", clientToken: "rum-abc", environment: "benchmarks")
                .set(customRUMEndpoint: anyURL)
                .build()
        )

        Logs.enable(
            with: Logs.Configuration(customIntakeURL: anyURL)
        )

        DatadogTracer.initialize(
            configuration: .init(customIntakeURL: anyURL)
        )
    }

    // MARK: - `HTTPServerMock` connection

    private static var connectedServer: ServerMock?

    private static func connectToServerIfNotConnected() throws {
        if BenchmarkTests.connectedServer != nil {
            return
        }

        let testsBundle = Bundle(for: BenchmarkTests.self)
        guard let serverAddress = testsBundle.object(forInfoDictionaryKey: "MockServerAddress") as? String else {
            throw ServerConnectionError(description: "Cannot obtain `MockServerAddress` from `Info.plist`")
        }

        guard let serverURL = URL(string: "http://\(serverAddress)") else {
            throw ServerConnectionError(description: "`MockServerAddress` obtained from `Info.plist` is invalid.")
        }

        let serverProcessRunner = ServerProcessRunner(serverURL: serverURL)
        guard let serverProcess = serverProcessRunner.waitUntilServerIsReachable() else {
            throw ServerConnectionError(
                description: "The server seems to be not running properly on \(serverURL.absoluteString)"
            )
        }

        print("🌍 Connected to mock server on \(serverURL.absoluteString)")

        BenchmarkTests.connectedServer = ServerMock(serverProcess: serverProcess)
    }
}
