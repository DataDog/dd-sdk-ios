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

    private struct OperationIdentity: Hashable {
        let name: String
        let key: String?
    }

    private struct OperationViewContext {
        let id: RUMUUID
        let name: String
        let path: String
        let attributes: [AttributeKey: AttributeValue]

        init(view: RUMViewScope) {
            self.id = view.viewUUID
            self.name = view.viewName
            self.path = view.viewPath
            self.attributes = view.attributes
        }

        private init(
            id: RUMUUID,
            name: String,
            path: String,
            attributes: [AttributeKey: AttributeValue]
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.attributes = attributes
        }

        var retainedSnapshot: OperationViewContext {
            OperationViewContext(
                id: id,
                name: name,
                path: path,
                attributes: [:]
            )
        }
    }

    private struct ActiveOperation {
        /// The scene that owned the operation start. Subsequent steps use the
        /// current view in this scene instead of the process representative.
        let sceneIdentifier: RUMSceneIdentifier?
        /// Last view proven to belong to the operation's scene. Retaining this
        /// lightweight snapshot lets an end step preserve its source after the
        /// scene closes without retaining the completed `RUMViewScope`.
        var viewContext: OperationViewContext?
    }

    /// Active operation state for tracking, warnings, and scene ownership.
    private var activeOperations: [OperationIdentity: ActiveOperation] = [:]
    private let maxActiveOperations = 500

    // MARK: - Dependencies

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies
    private let sessionSampler: DeterministicSampler
    private let sanitizer = RUMEventSanitizer()

    // MARK: - Initialization

    init(parent: RUMContextProvider, dependencies: RUMScopeDependencies, sessionSampler: DeterministicSampler) {
        self.parent = parent
        self.dependencies = dependencies
        self.sessionSampler = sessionSampler
    }

    // MARK: - Public Interface

    @discardableResult
    func process(
        _ command: RUMOperationStepVitalCommand,
        context: DatadogContext,
        writer: Writer,
        activeView: RUMViewScope?,
        activeViews: [RUMViewScope] = []
    ) -> RUMViewScope? {
        // Validate command parameters
        guard validateCommand(command) else {
            return nil
        }

        let identity = OperationIdentity(name: command.name, key: command.operationKey)
        let operationView = view(
            for: command,
            identity: identity,
            representativeView: activeView,
            activeViews: activeViews
        )
        let operationViewContext = viewContext(
            for: command,
            identity: identity,
            activeView: operationView
        )

        if operationViewContext == nil {
            DD.logger.warn("RUM operation step command received without an active view. This may result in incomplete context information.")
        }

        // Always create and send the vital event - this is the SDK's core responsibility
        writeVitalEvent(
            from: command,
            context: context,
            writer: writer,
            viewContext: operationViewContext
        )

        // Track operation state for troubleshooting warnings
        switch command.stepType {
        case .start:
            trackOperationStart(
                name: command.name,
                operationKey: command.operationKey,
                identity: identity,
                sceneIdentifier: operationView?.sceneIdentifier,
                viewContext: operationViewContext
            )

        case .end, .update, .retry:
            trackOperationUpdate(
                name: command.name,
                operationKey: command.operationKey,
                identity: identity,
                stepType: command.stepType,
                viewContext: operationViewContext
            )
        }

        return operationView
    }

    // MARK: - Private Methods

    private func writeVitalEvent(
        from command: RUMOperationStepVitalCommand,
        context: DatadogContext,
        writer: Writer,
        viewContext: OperationViewContext?
    ) {
        let vital = RUMVitalOperationStepEvent.Vital(
            failureReason: command.failureReason,
            id: command.vitalId,
            name: command.name,
            operationKey: command.operationKey,
            stepType: command.stepType
        )

        let mergedAttributes = command.globalAttributes
            .merging(parent.attributes) { $1 }
            .merging(viewContext?.attributes ?? [:]) { $1 }
            .merging(command.attributes) { $1 }

        let profiling = context.additionalContext(ofType: ProfilingContext.self)?.ddProfiling

        if shouldSendOperationMessage(for: command) {
            let message = OperationMessage(
                attributes: rumContextAttributes(for: viewContext),
                operation: Vital(
                    id: command.vitalId,
                    name: command.name,
                    operationKey: command.operationKey,
                    stepType: command.stepType,
                    date: command.time,
                    serverTimeOffset: context.serverTimeOffset
                )
            )
            dependencies.featureScope.send(message: .payload(message))
        }

        let vitalEvent = RUMVitalOperationStepEvent(
            dd: .init(profiling: profiling),
            account: .init(context: context),
            application: .init(id: parent.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: mergedAttributes),
            date: command.time.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
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
                id: (viewContext?.id).orNull.toRUMDataFormat,
                url: viewContext?.path ?? ""
            ),
            vital: vital
        )

        writer.write(value: sanitizer.sanitize(event: vitalEvent))
    }

    /// Builds the operation correlation from the session context and overlays the
    /// selected view. Reading `activeView.context` would walk through the view's
    /// unowned parent even though the manager already owns the same session
    /// context, and is unnecessary for operation messages.
    private func rumContextAttributes(for viewContext: OperationViewContext?) -> [String: AttributeValue] {
        var attributes = parent.rumContextAttributes

        if let viewContext {
            attributes[RUMCoreContext.IDs.viewID] = [viewContext.id.toRUMDataFormat]
            attributes[RUMCoreContext.IDs.viewName] = [viewContext.name]
        } else {
            // The parent context describes the process representative and may
            // belong to another concurrently active scene. Leave the view
            // unset when no originating context is known.
            attributes.removeValue(forKey: RUMCoreContext.IDs.viewID)
            attributes.removeValue(forKey: RUMCoreContext.IDs.viewName)
        }

        return attributes
    }

    private func shouldSendOperationMessage(for command: RUMOperationStepVitalCommand) -> Bool {
        switch command.stepType {
        case .start:
            guard let options = command.options as? ProfilingOptions else {
                return false
            }
            return sessionSampler.combined(with: options.sampleRate).sample()
        case .end:
            return true
        case .update, .retry:
            return false
        }
    }

    private func trackOperationStart(
        name: String,
        operationKey: String?,
        identity: OperationIdentity,
        sceneIdentifier: RUMSceneIdentifier?,
        viewContext: OperationViewContext?
    ) {
        // Check if operation is already being tracked
        if activeOperations[identity] != nil {
            // Warning: Operation appears to be started multiple times
            DD.logger.warn("Operation \(formatOperationName(name, operationKey: operationKey)) has already been started. This may result in the backend terminating the previous instance with an `auto_restart` failure. Note that the SDK only tracks operations locally and not across sessions.")
        }

        cleanUpActiveOperations()

        // Add operation to local tracking for future reference
        activeOperations[identity] = ActiveOperation(
            sceneIdentifier: sceneIdentifier,
            viewContext: viewContext?.retainedSnapshot
        )
    }

    private func trackOperationUpdate(
        name: String,
        operationKey: String?,
        identity: OperationIdentity,
        stepType: RUMVitalOperationStepEvent.Vital.StepType,
        viewContext: OperationViewContext?
    ) {
        // Check if operation is currently being tracked
        if activeOperations[identity] == nil {
            // Warning: Operation step called without a corresponding start
            DD.logger.warn("`\(stepType.rawValue)` was called, but operation \(formatOperationName(name, operationKey: operationKey)) is currently not active. This may lead to a backend `instrumentation_error`. Make sure to call `startOperation(name:operationKey:attributes:options:)` first. Note that the SDK only tracks operations locally and not across sessions.")
        }

        if var operation = activeOperations[identity], let viewContext {
            operation.viewContext = viewContext.retainedSnapshot
            activeOperations[identity] = operation
        }

        // Remove operation from tracking when it ends
        if stepType == .end {
            activeOperations.removeValue(forKey: identity)
        }
    }

    // MARK: Utility Methods

    /// Validates the `name` and `operationKey` of the command
    private func validateCommand(_ command: RUMOperationStepVitalCommand) -> Bool {
        // Validate name (required)
        guard validateName(command.name, stepType: command.stepType) else {
            return false
        }

        // Validate operationKey if present (optional)
        if let operationKey = command.operationKey,
           !validateOperationKey(operationKey, stepType: command.stepType) {
            return false
        }

        return true
    }

    /// ASCII character set accepted by the backend for `vital.name`, matching
    /// the server-side regex `[\w.@$-]` (letters, digits, `_`, `.`, `@`, `$`,
    /// `-`). Built explicitly from ASCII so that Unicode-aware categories
    /// (which `CharacterSet.alphanumerics` would pull in) do not mask
    /// non-conforming names — e.g. `ログイン` is all Unicode "Letter, other"
    /// and must still trigger the warning.
    private static let validOperationNameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@$-"
    )

    /// Validates the operation name.
    ///
    /// Blank / empty names are rejected (the backend rejects them with its
    /// own non-empty precondition before evaluating the character-set regex).
    /// Names that fail the backend's `[\w.@$-]*` character-set regex trigger
    /// a developer warning but the event is still emitted — the backend is
    /// the source of truth on character-set policy, so client-side drop
    /// would force an SDK bump if that policy is ever relaxed.
    private func validateName(_ value: String, stepType: RUMVitalOperationStepEvent.Vital.StepType) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            DD.logger.error("Operation `name` cannot be empty or contain only whitespace/line breaks. \(stepType) command will be ignored.")
            return false
        }

        if !value.unicodeScalars.allSatisfy(Self.validOperationNameCharacters.contains) {
            DD.logger.warn("Operation `name` '\(value)' does not match the backend-accepted pattern [\\w.@$-]* (letters, digits, _ . @ $ -). The \(stepType) command will still be emitted and may be rejected by the backend.")
        }

        return true
    }

    /// Validates the operation key: non-blank. The schema does not restrict
    /// the character set for `operation_key`.
    /// A blank value is warned about but the event is still emitted — `operationKey`
    /// is optional, so a blank value should not discard the entire operation step.
    private func validateOperationKey(_ value: String, stepType: RUMVitalOperationStepEvent.Vital.StepType) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            DD.logger.warn("Operation `operationKey`, when provided, cannot be empty or contain only whitespace/line breaks. The \(stepType) command will still be emitted.")
        }

        return true
    }

    /// Keeps the number of active operations below the maximum allowed
    private func cleanUpActiveOperations() {
        if activeOperations.count > maxActiveOperations,
           let oldestOperation = activeOperations.keys.first {
            activeOperations.removeValue(forKey: oldestOperation)
        }
    }

    private func view(
        for command: RUMOperationStepVitalCommand,
        identity: OperationIdentity,
        representativeView: RUMViewScope?,
        activeViews: [RUMViewScope]
    ) -> RUMViewScope? {
        guard command.stepType != .start,
              let operation = activeOperations[identity] else {
            return representativeView
        }

        guard let sceneIdentifier = operation.sceneIdentifier else {
            return representativeView
        }

        return activeViews.last {
            $0.isActiveView && $0.sceneIdentifier == sceneIdentifier
        }
    }

    private func viewContext(
        for command: RUMOperationStepVitalCommand,
        identity: OperationIdentity,
        activeView: RUMViewScope?
    ) -> OperationViewContext? {
        if let activeView {
            return OperationViewContext(view: activeView)
        }

        guard command.stepType != .start,
              let operation = activeOperations[identity],
              operation.sceneIdentifier != nil else {
            return nil
        }

        return operation.viewContext
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
