/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

/*
 * This class is responsible for processing RUM `operation_step` Vital commands and creating corresponding Vital events.
 * 
 * Key responsibilities:
 * - Always processes operation step commands and creates vital events (SDK's primary responsibility)
 * - Tracks active operations locally for troubleshooting purposes only
 * - Provides helpful warning messages for common API misuse patterns
 * 
 * Important: The SDK is NOT responsible for:
 * - Validating operation lifecycle
 * - Calculating operation duration or status
 * - Creating the final operation object
 * 
 * Local operation tracking is purely for developer experience and debugging.
 */

internal class RUMFeatureOperationManager {
    // MARK: - Properties

    /// Set of active operation lookup keys for tracking and warning purposes
    /// Key format: "operationName" + "operationKey" (if any)
    private var activeOperations: Set<String> = []
    private let maxActiveOperations = 500

    // MARK: - Dependencies

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    // MARK: - Initialization

    init(parent: RUMContextProvider, dependencies: RUMScopeDependencies) {
        self.parent = parent
        self.dependencies = dependencies
    }

    // MARK: - Public Interface

    func process(_ command: RUMOperationStepVitalCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        // Validate command parameters
        guard validateCommand(command) else {
            return
        }

        if activeView == nil {
            DD.logger.warn("RUM operation step command received without an active view. This may result in incomplete context information.")
        }

        // Always create and send the vital event - this is the SDK's core responsibility
        writeVitalEvent(
            from: command,
            context: context,
            writer: writer,
            activeView: activeView
        )

        let lookupKey = "\(command.name)\(command.operationKey ?? "")"

        // Track operation state for troubleshooting warnings
        switch command.stepType {
        case .start:
            trackOperationStart(name: command.name, operationKey: command.operationKey, lookupKey: lookupKey)

        case .end, .update, .retry:
            trackOperationUpdate(name: command.name, operationKey: command.operationKey, lookupKey: lookupKey, stepType: command.stepType)
        }
    }

    // MARK: - Private Methods

    private func writeVitalEvent(from command: RUMOperationStepVitalCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        let vital = RUMVitalOperationStepEvent.Vital(
            failureReason: command.failureReason,
            id: command.vitalId,
            name: command.name,
            operationKey: command.operationKey,
            stepType: command.stepType
        )

        let mergedAttributes = command.globalAttributes
            .merging(parent.attributes) { $1 }
            .merging(activeView?.attributes ?? [:]) { $1 }
            .merging(command.attributes) { $1 }

        let vitalEvent = RUMVitalOperationStepEvent(
            dd: .init(),
            account: .init(context: context),
            application: .init(id: parent.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: mergedAttributes),
            date: command.time.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            ddtags: context.ddTags,
            device: context.normalizedDevice(),
            display: nil,
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: parent.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: (activeView?.viewUUID).orNull.toRUMDataFormat,
                url: activeView?.viewPath ?? ""
            ),
            vital: vital
        )

        writer.write(value: vitalEvent)
    }

    private func trackOperationStart(name: String, operationKey: String?, lookupKey: String) {
        // Check if operation is already being tracked
        if activeOperations.contains(lookupKey) {
            // Warning: Operation appears to be started multiple times
            DD.logger.warn("Operation \(formatOperationName(name, operationKey: operationKey)) has already been started. This may result in the backend terminating the previous instance with an `auto_restart` failure. Note that the SDK only tracks operations locally and not across sessions.")
        }

        cleanUpActiveOperations()

        // Add operation to local tracking for future reference
        activeOperations.insert(lookupKey)
    }

    private func trackOperationUpdate(name: String, operationKey: String?, lookupKey: String, stepType: RUMVitalOperationStepEvent.Vital.StepType) {
        // Check if operation is currently being tracked
        if !activeOperations.contains(lookupKey) {
            // Warning: Operation step called without a corresponding start
            DD.logger.warn("`\(stepType.rawValue)` was called, but operation \(formatOperationName(name, operationKey: operationKey)) is currently not active. This may lead to a backend `instrumentation_error`. Make sure to call `startFeatureOperation(name:operationKey:attributes:)` first. Note that the SDK only tracks operations locally and not across sessions.")
        }

        // Remove operation from tracking when it ends
        if stepType == .end {
            activeOperations.remove(lookupKey)
        }
    }

    // MARK: Utility Methods

    /// Validates the `name` and `operationKey` of the command
    private func validateCommand(_ command: RUMOperationStepVitalCommand) -> Bool {
        // Validate name (required)
        guard validateString(command.name, stepType: command.stepType) else {
            return false
        }

        // Validate operationKey if present (optional)
        if let operationKey = command.operationKey,
           !validateString(operationKey, stepType: command.stepType) {
            return false
        }

        return true
    }

    /// Validates the string is not empty
    // or contains only whitespace/line breaks
    private func validateString(_ value: String, stepType: RUMVitalOperationStepEvent.Vital.StepType) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            DD.logger.error("Operation `name` and `operationKey` cannot be empty or contain only whitespace/line breaks. \(stepType) command will be ignored.")
            return false
        }

        // Backend takes care of sanitizing user inputs
        return true
    }

    /// Keeps the number of active operations below the maximum allowed
    private func cleanUpActiveOperations() {
        if activeOperations.count > maxActiveOperations {
            activeOperations.removeFirst()
        }
    }

    /// Formats operation name and key for consistent warning message display
    private func formatOperationName(_ name: String, operationKey: String?) -> String {
        if let operationKey {
            return "`\(name)` (key `\(operationKey)`)"
        } else {
            return "`\(name)`"
        }
    }
}
