/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import TestUtilities
@testable import DatadogCore

extension AppRunner {
    /// The Datadog SDK core proxy created by `initializeSDK(_:)`. Backed by `state["core"]`.
    /// Crashes (IUO semantics) if accessed before SDK initialization.
    var core: DatadogCoreProxy! {
        get { state["core"] as? DatadogCoreProxy }
        set {
            if let newValue {
                state["core"] = newValue
            } else {
                state.removeValue(forKey: "core")
            }
        }
    }

    // MARK: - SDK Setup

    /// Typealias for SDK configuration closure.
    typealias SDKSetup = (inout Datadog.Configuration) -> Void

    /// Initializes the SDK using an optional setup block.
    func initializeSDK(_ sdkSetup: SDKSetup = { _ in }) {
        var config = Datadog.Configuration(clientToken: "mock-client-token", env: "env")
        let url = appDirectoryURL!
        config.systemDirectory = { Directory(url: url) }
        config.processInfo = processInfo
        config.dateProvider = dateProvider
        config.notificationCenter = notificationCenter
        config.appLaunchHandler = appLaunchHandler
        config.appStateProvider = appStateProvider
        config.serverDateProvider = ServerDateProviderMock()
        sdkSetup(&config)
        do {
            core = DatadogCoreProxy(
                core: try DatadogCore(configuration: config, trackingConsent: .granted, instanceName: .mockAny())
            )
        } catch {
            preconditionFailure("\(error)")
        }
    }

    // MARK: - Process Info

    /// Sets process launch arguments on the mock `ProcessInfo`. Must be called BEFORE
    /// `initializeSDK()` because the SDK reads arguments from `configuration.processInfo`
    /// at config time (e.g., `Logger.swift` reads `LaunchArguments.Debug` at logger creation).
    func setProcessArguments(_ args: [String]) {
        let env = processInfo.environment
        processInfo = ProcessInfoMock(environment: env, arguments: args)
    }

    // MARK: - User Info

    /// Sets user info on the SDK core.
    func setUserInfo(id: String? = nil, name: String? = nil, email: String? = nil, extraInfo: [AttributeKey: AttributeValue] = [:]) {
        core.setUserInfo(id: id, name: name, email: email, extraInfo: extraInfo)
    }

    /// Adds extra info to the current user.
    func addUserExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        core.addUserExtraInfo(newExtraInfo)
    }

    /// Clears user info on the SDK core.
    func clearUserInfo() {
        core.clearUserInfo()
    }

    // MARK: - Data Retrieval

    /// Flushes all pending SDK operations synchronously.
    func flush() {
        core.flush()
    }
}
