/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class CrashReportingFeature: DatadogFeature {
    static let name = "crash-reporter"

    let messageReceiver: FeatureMessageReceiver
    let crashContextProvider: CrashContextProvider

    private let coordinator: CrashReportCoordinator

    /// JSON encoder used for writing `CrashContext` into JSON `Data` injected to crash report.
    /// Note: this `JSONEncoder` must have the same configuration as the `JSONEncoder` used later for writing payloads to uploadable files.
    /// Otherwise the format of data read and uploaded from crash report context will be different than the format of data retrieved from the user
    /// and written directly to uploadable file.
    internal static let crashContextEncoder: JSONEncoder = .dd.default()
    /// JSON decoder used for reading `CrashContext` from JSON `Data` injected to crash report.
    /// Note: it must follow a configuration that enables reading data encoded with `crashContextEncoder`.
    internal static let crashContextDecoder: JSONDecoder = {
        var decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            guard let date = iso8601DateFormatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: Requires ISO8601.")
            }
            return date
        }
        return decoder
    }()

    init(
        crashReportingPlugin: CrashReportingPlugin,
        crashContextProvider: CrashContextProvider,
        sender: CrashReportSender,
        messageReceiver: FeatureMessageReceiver,
        telemetry: Telemetry
    ) {
        self.coordinator = CrashReportCoordinator(
            plugin: crashReportingPlugin,
            sender: sender,
            telemetry: telemetry
        )
        self.crashContextProvider = crashContextProvider
        self.messageReceiver = messageReceiver

        if let context = crashContextProvider.currentCrashContext {
            Task { [coordinator] in await coordinator.inject(currentCrashContext: context) }
        }

        self.crashContextProvider.onCrashContextChange = { [weak coordinator] context in
            Task { await coordinator?.inject(currentCrashContext: context) }
        }
    }

    // MARK: - Interaction with `DatadogCrashReporting` plugin

    @discardableResult
    func sendCrashReportIfFound() -> Task<Void, Never> {
        coordinator.sendCrashReportIfFound()
    }
}

// MARK: - CrashReportCoordinator

/// Coordinates crash report operations with actor isolation.
internal actor CrashReportCoordinator {
    private let plugin: CrashReportingPlugin
    private let sender: CrashReportSender
    private let telemetry: Telemetry

    init(
        plugin: CrashReportingPlugin,
        sender: CrashReportSender,
        telemetry: sending Telemetry
    ) {
        self.plugin = plugin
        self.sender = sender
        self.telemetry = telemetry
    }

    func inject(currentCrashContext: CrashContext) {
        if let crashContextData = encode(crashContext: currentCrashContext) {
            plugin.inject(context: crashContextData)
        }
    }

    nonisolated func sendCrashReportIfFound() -> Task<Void, Never> {
        Task {
            await self.performSendCrashReportIfFound()
        }
    }

    // MARK: - Private

    private func performSendCrashReportIfFound() async {
        let crashReport = await plugin.readPendingCrashReport()

        guard let crashReport else {
            DD.logger.debug("No pending Crash found")
            sender.send(launch: .init(didCrash: false))
            return
        }

        DD.logger.debug("Loaded pending crash report")

        guard let crashContext = crashReport.context.flatMap({ decode(crashContextData: $0) }) else {
            sender.send(launch: .init(didCrash: true))
            plugin.deletePendingCrashReports()
            return
        }

        sender.send(report: crashReport, with: crashContext)
        sender.send(launch: .init(didCrash: true))
        plugin.deletePendingCrashReports()
    }

    private func encode(crashContext: CrashContext) -> Data? {
        do {
            return try CrashReportingFeature.crashContextEncoder.encode(crashContext)
        } catch {
            DD.logger.error(
                """
                Failed to encode crash report context. The app state information associated with eventual crash
                report may be not in sync with the current state of the application.
                """,
                error: error
            )
            telemetry.error("Failed to encode crash report context", error: error)
            return nil
        }
    }

    private func decode(crashContextData: Data) -> CrashContext? {
        do {
            return try CrashReportingFeature.crashContextDecoder.decode(CrashContext.self, from: crashContextData)
        } catch {
            DD.logger.error(
                """
                Failed to decode crash report context. The app state information associated with the crash
                report won't be in sync with the state of the application when it crashed.
                """,
                error: error
            )
            telemetry.error("Failed to decode crash report context", error: error)
            return nil
        }
    }
}
