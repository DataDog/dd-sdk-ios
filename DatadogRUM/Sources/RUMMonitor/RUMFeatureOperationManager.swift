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

    // MARK: - Dependencies

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    // MARK: - Initialization

    init(parent: RUMContextProvider, dependencies: RUMScopeDependencies) {
        self.parent = parent
        self.dependencies = dependencies
    }

    // MARK: - Public Interface

    func process(_ command: RUMOperationStepVitalCommand, context: DatadogContext, writer: Writer, activeViewID: String, activeViewPath: String) {
        let lookupKey = "\(command.name)\(command.operationKey ?? "")"

        // Always create and send the vital event - this is the SDK's core responsibility
        writeVitalEvent(from: command, context: context, writer: writer, activeViewID: activeViewID, activeViewPath: activeViewPath)

        // Track operation state for troubleshooting warnings
        switch command.stepType {
        case .start:
            trackOperationStart(name: command.name, operationKey: command.operationKey, lookupKey: lookupKey)

        case .end, .update, .retry:
            trackOperationUpdate(name: command.name, operationKey: command.operationKey, lookupKey: lookupKey, stepType: command.stepType)
        }
    }

    // MARK: - Private Methods

    private func writeVitalEvent(from command: RUMOperationStepVitalCommand, context: DatadogContext, writer: Writer, activeViewID: String, activeViewPath: String) {
        guard !command.name.isEmpty else {
            DD.logger.error("Operations must have a non-empty name. \(command) call will be ignored.")
            return
        }

        let vital = RUMVitalEvent.Vital(
            vitalDescription: nil,
            duration: nil,
            failureReason: command.failureReason,
            id: command.vitalId,
            name: command.name,
            operationKey: command.operationKey,
            stepType: command.stepType,
            type: .operationStep
        )

        let vitalEvent = RUMVitalEvent(
            dd: .init(),
            application: .init(id: parent.context.rumApplicationID),
            context: .init(contextInfo: command.globalAttributes.merging(command.attributes) { $1 }),
            date: command.time.timeIntervalSince1970.toInt64Milliseconds,
            session: .init(
                hasReplay: context.hasReplay,
                id: parent.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            view: .init(
                id: activeViewID,
                url: activeViewPath
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

        // Add operation to local tracking for future reference
        activeOperations.insert(lookupKey)
    }

    private func trackOperationUpdate(name: String, operationKey: String?, lookupKey: String, stepType: RUMVitalEvent.Vital.StepType) {
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

    /// Formats operation name and key for consistent warning message display
    private func formatOperationName(_ name: String, operationKey: String?) -> String {
        if let operationKey {
            return "`\(name)` (key `\(operationKey)`)"
        } else {
            return "`\(name)`"
        }
    }
}
