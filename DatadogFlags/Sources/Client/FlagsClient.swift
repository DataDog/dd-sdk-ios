/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A client for evaluating feature flags in your application.
///
/// `FlagsClient` provides methods to evaluate feature flags with type-safe access to flag values.
/// Each client maintains its own evaluation context and can be used independently throughout your application.
///
/// ## Overview
///
/// Create a client after enabling the Flags feature:
///
/// ```swift
/// // Create the default client
/// let client = FlagsClient.create()
///
/// // Set evaluation context (user/session information)
/// client.setEvaluationContext(
///     FlagsEvaluationContext(
///         targetingKey: "user-123",
///         attributes: [
///             "email": .string("user@example.com"),
///             "tier": .string("premium")
///         ]
///     )
/// )
///
/// // Evaluate flags
/// let showNewFeature = client.getBooleanValue(key: "show-new-feature", defaultValue: false)
/// let themeColor = client.getStringValue(key: "theme-color", defaultValue: "blue")
/// ```
public final class FlagsClient {
    /// Controls how the client applies each subject's `dd_experimentation_opt_out_at` timestamp.
    public enum ExperimentationOptOutMode {
        /// Ignore the `dd_experimentation_opt_out_at` context attribute.
        case disabled
        /// Exclude subjects with a valid opt-out timestamp from experiment allocations immediately.
        /// This includes future timestamps. Ordinary feature allocations remain available.
        case immediate
        /// Exclude experiment allocations activated at or after the subject's opt-out timestamp.
        /// Experiment allocations with unknown activation times are also excluded.
        /// Ordinary allocations and older experiments remain available.
        case futureExperimentsOnly
    }

    /// Configuration for an individual Flags client.
    public struct Configuration {
        /// Controls how the client applies the subject's `dd_experimentation_opt_out_at` timestamp.
        /// The default is `.disabled`. This does not change evaluation telemetry settings.
        public var experimentationOptOutMode: ExperimentationOptOutMode

        /// Enables per-subject opt-out from customer-facing feature flag evaluation reporting.
        ///
        /// This controls flag evaluation reporting, not Datadog SDK internal telemetry.
        /// Do not use it to disable SDK diagnostics.
        ///
        /// When enabled, setting `dd_evaluation_telemetry_opt_out` to boolean `true` suppresses new evaluation events,
        /// evaluation counts, and automatic RUM flag annotations.
        /// Before the first context update, evaluation telemetry is also suppressed until the cached policy is loaded.
        /// Flag evaluation and experiment exposure logging remain unchanged.
        /// Previously recorded telemetry is not removed.
        /// The attribute remains available for targeting and exposure reporting.
        ///
        /// Default: `false`.
        public var enableEvaluationTelemetryOptOutParameter: Bool

        /// Creates configuration for an individual Flags client.
        /// - Parameters:
        ///   - enableEvaluationTelemetryOptOutParameter: Enables per-subject opt-out from flag evaluation data,
        ///   not SDK internal telemetry. Suppresses while the initial cached policy is unknown, then requires
        ///   `dd_evaluation_telemetry_opt_out` to be boolean `true`.
        ///   Default: `false`.
        ///   - experimentationOptOutMode: How to apply the subject's `dd_experimentation_opt_out_at` timestamp. Default: `.disabled`.
        public init(
            enableEvaluationTelemetryOptOutParameter: Bool = false,
            experimentationOptOutMode: ExperimentationOptOutMode = .disabled
        ) {
            self.enableEvaluationTelemetryOptOutParameter = enableEvaluationTelemetryOptOutParameter
            self.experimentationOptOutMode = experimentationOptOutMode
        }

        /// Creates configuration for an individual Flags client.
        ///
        /// Preserves the initializer exported by earlier releases for binary compatibility.
        public init(enableEvaluationTelemetryOptOutParameter: Bool) {
            self.init(
                enableEvaluationTelemetryOptOutParameter: enableEvaluationTelemetryOptOutParameter,
                experimentationOptOutMode: .disabled
            )
        }
    }

    /// The default client name used when no name is specified.
    ///
    /// Use this constant when you need to reference the default client by name.
    public static let defaultName = "default"

    private enum EvaluationError {
        static let providerNotReady = "PROVIDER_NOT_READY"
        static let providerFatal = "PROVIDER_FATAL"
        static let flagNotFound = "FLAG_NOT_FOUND"
        static let parseError = "PARSE_ERROR"
        static let typeMismatch = "TYPE_MISMATCH"
        static let targetingKeyMissing = "TARGETING_KEY_MISSING"
        static let invalidContext = "INVALID_CONTEXT"
        static let general = "GENERAL"
    }

    private let repository: any FlagsRepositoryProtocol
    private let exposureLogger: any ExposureLogging
    private let evaluationLogger: any EvaluationLogging
    private let rumFlagEvaluationReporter: any RUMFlagEvaluationReporting
    private let configuration: Configuration

    private static let telemetryOptOutAttribute = "dd_evaluation_telemetry_opt_out"
    private static let defaultAssignment = FlagAssignment(
        allocationKey: "",
        variationKey: "",
        variation: .unknown(""),
        reason: "DEFAULT",
        doLog: false
    )

    internal init(
        repository: any FlagsRepositoryProtocol,
        exposureLogger: any ExposureLogging,
        evaluationLogger: any EvaluationLogging,
        rumFlagEvaluationReporter: any RUMFlagEvaluationReporting,
        configuration: Configuration = .init()
    ) {
        self.repository = repository
        self.exposureLogger = exposureLogger
        self.evaluationLogger = evaluationLogger
        self.rumFlagEvaluationReporter = rumFlagEvaluationReporter
        self.configuration = configuration
    }

    /// Creates a new `FlagsClient` instance.
    ///
    /// Use this method to create a client for evaluating feature flags. The client is registered internally
    /// by name, so you don't need to keep a reference to it. Access the same client from anywhere in your
    /// app using ``shared(named:in:)``.
    ///
    /// If a client with the same name already exists, the existing client is returned and a warning is logged.
    ///
    /// ```swift
    /// // Create the default client (typically in app initialization)
    /// FlagsClient.create()
    ///
    /// // Later, access it from anywhere without keeping a reference
    /// let client = FlagsClient.shared()
    /// let isEnabled = client.getBooleanValue(key: "new-feature", defaultValue: false)
    ///
    /// // Create named clients for different modules
    /// FlagsClient.create(name: "checkout")
    /// FlagsClient.create(name: "recommendations")
    ///
    /// // Access them from different parts of your app
    /// let checkoutClient = FlagsClient.shared(named: "checkout")
    /// let recsClient = FlagsClient.shared(named: "recommendations")
    /// ```
    ///
    /// - Parameters:
    ///   - name: A unique name for this client. Defaults to ``defaultName``.
    ///   - core: The Datadog SDK core instance. Defaults to the global shared instance.
    ///
    /// - Returns: A `FlagsClientProtocol` instance for evaluating flags.
    ///
    /// - Important: ``Flags/enable(with:in:)`` must be called before creating clients.
    ///
    /// - Note: Clients are retained internally, so you don't need to keep references to them.
    @discardableResult
    public static func create(
        name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        create(configuration: .init(), name: name, in: core)
    }

    /// Creates a client with its own configuration.
    ///
    /// Clients are retained by name. If the name already exists, its original configuration remains in effect.
    /// Enable the Flags feature before creating clients.
    ///
    /// - Parameters:
    ///   - configuration: Configuration for this client.
    ///   - name: A unique client name. Defaults to ``defaultName``.
    ///   - core: The Datadog SDK core instance. Defaults to the global shared instance.
    /// - Returns: A client for evaluating flags.
    @discardableResult
    public static func create(
        configuration: Configuration,
        name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        // To ensure the correct registration order between Core and Features,
        // the entire initialization flow is synchronized on the main thread.
        runOnMainThreadSync {
            doCreate(name: name, configuration: configuration, in: core)
        }
    }

    /// Returns an existing `FlagsClient` instance by name.
    ///
    /// Use this method to retrieve a client that was previously created with ``create(name:in:)``.
    /// If no client with the specified name exists, a no-op client is returned and a warning is logged.
    ///
    /// ```swift
    /// // Get the default client
    /// let client = FlagsClient.shared()
    ///
    /// // Get a named client
    /// let checkoutClient = FlagsClient.shared(named: "checkout")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the client to retrieve. Defaults to ``defaultName``.
    ///   - core: The Datadog SDK core instance. Defaults to the global shared instance.
    ///
    /// - Returns: A `FlagsClientProtocol` instance. Returns a no-op client if the requested client doesn't exist.
    ///
    /// - Important: The client must first be created with ``create(name:in:)``.
    public static func shared(
        named name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        guard
            let clientRegistry = core.get(feature: FlagsFeature.self)?.clientRegistry,
            let client = clientRegistry.client(named: name)
        else {
            reportIssue(
                """
                Attempted to use a `FlagsClient` named '\(name)', but no such client exists. \
                Create the client with `FlagsClient.create(name:in:)` before using it. \
                Operating in no-op mode.
                """,
                in: core
            )
            return FallbackFlagsClient(name: name, core: core)
        }

        return client
    }

    internal static func doCreate(
        name: String,
        configuration: Configuration,
        in core: DatadogCoreProtocol
    ) -> FlagsClientProtocol {
        guard let feature = core.get(feature: FlagsFeature.self) else {
            reportIssue(
                """
                Failed to create `FlagsClient` named '\(name)': Flags feature must be enabled first. \
                Call `Flags.enable()` before creating clients. \
                Operating in no-op mode.
                """,
                in: core
            )
            return FallbackFlagsClient(name: name, core: core)
        }

        if let client = feature.clientRegistry.client(named: name) {
            if let existing = client as? FlagsClient,
               existing.configuration.experimentationOptOutMode != configuration.experimentationOptOutMode {
                reportIssue(
                    """
                    Attempted to create a `FlagsClient` named '\(name)' with experimentation opt-out mode \
                    `.\(configuration.experimentationOptOutMode)`, but one already exists with mode \
                    `.\(existing.configuration.experimentationOptOutMode)`. \
                    The existing client will be used, and new configuration will be ignored.
                    """,
                    in: core
                )
                return client
            }
            reportIssue(
                """
                Attempted to create a `FlagsClient` named '\(name)', but one already exists. \
                The existing client will be used, and new configuration will be ignored.
                """,
                in: core
            )
            return client
        }

        let featureScope = core.scope(for: FlagsFeature.self)
        let client = FlagsClient(
            repository: FlagsRepository(
                clientName: name,
                flagAssignmentsFetcher: feature.flagAssignmentsFetcher,
                dateProvider: SystemDateProvider(),
                featureScope: featureScope,
                initializationTimeout: feature.initializationTimeout,
                experimentationOptOutMode: configuration.experimentationOptOutMode
            ),
            exposureLogger: feature.makeExposureLogger(featureScope),
            evaluationLogger: feature.makeEvaluationLogger(featureScope),
            rumFlagEvaluationReporter: feature.makeRUMFlagEvaluationReporter(featureScope),
            configuration: configuration
        )

        feature.clientRegistry.register(client, named: name)
        return client
    }
}

extension FlagsClient: FlagsClientProtocol {
    @discardableResult
    public func onFirstFlags(_ listener: @escaping FlagsClientEventListener) -> any FlagsSubscription {
        repository.onFirstFlags(listener)
    }

    public var state: FlagsStateObservable {
        repository.state
    }

    public func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        repository.setEvaluationContext(context, completion: completion)
    }

    public func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        let snapshot = repository.evaluationSnapshot(for: key)
        let context = snapshot.context
        let trackEvaluationTelemetry = !configuration.enableEvaluationTelemetryOptOutParameter || !snapshot.telemetryOptedOut

        if snapshot.error == .invalidContext {
            logEvaluation(
                enabled: trackEvaluationTelemetry,
                for: key,
                assignment: Self.defaultAssignment,
                evaluationContext: snapshot.requestedContext ?? .empty,
                flagError: EvaluationError.invalidContext
            )
            return FlagDetails(key: key, value: defaultValue, error: .invalidContext)
        }

        guard let context else {
            logEvaluation(
                enabled: trackEvaluationTelemetry,
                for: key,
                assignment: Self.defaultAssignment,
                evaluationContext: snapshot.requestedContext ?? .empty,
                flagError: EvaluationError.providerNotReady
            )
            return FlagDetails(key: key, value: defaultValue, error: .providerNotReady)
        }

        guard let flagAssignment = snapshot.assignment else {
            logEvaluation(
                enabled: trackEvaluationTelemetry,
                for: key,
                assignment: Self.defaultAssignment,
                evaluationContext: context,
                flagError: EvaluationError.flagNotFound
            )
            return FlagDetails(key: key, value: defaultValue, error: .flagNotFound)
        }

        guard let value = flagAssignment.variation(as: T.self) else {
            logEvaluation(
                enabled: trackEvaluationTelemetry,
                for: key,
                assignment: flagAssignment,
                evaluationContext: context,
                flagError: EvaluationError.typeMismatch
            )
            return FlagDetails(key: key, value: defaultValue, error: .typeMismatch)
        }

        let details = FlagDetails(
            key: key,
            value: value,
            variant: flagAssignment.variationKey,
            reason: flagAssignment.reason,
            allocationKey: flagAssignment.allocationKey.isEmpty ? nil : flagAssignment.allocationKey
        )

        trackEvaluation(key: key, assignment: flagAssignment, context: context, trackEvaluationTelemetry: trackEvaluationTelemetry)

        return details
    }

    private func trackEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext, trackEvaluationTelemetry: Bool) {
        sendFlagExposure(key: key, assignment: assignment, context: context)

        guard trackEvaluationTelemetry else {
            return
        }

        // Log directly instead of calling sendFlagEvaluationEvent, which would check context again.
        // During a refresh, that context can be stale; use the snapshot's opt-out policy above.
        evaluationLogger.logEvaluation(
            for: key,
            assignment: assignment,
            evaluationContext: context,
            flagError: nil
        )

        rumFlagEvaluationReporter.sendFlagEvaluation(
            flagKey: key,
            value: assignment.variationKey
        )
    }

    private func logEvaluation(
        enabled: Bool,
        for key: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext,
        flagError: String
    ) {
        guard enabled else {
            return
        }
        evaluationLogger.logEvaluation(for: key, assignment: assignment, evaluationContext: evaluationContext, flagError: flagError)
    }

    private func isEvaluationTelemetryOptedOut(in context: FlagsEvaluationContext?) -> Bool {
        configuration.enableEvaluationTelemetryOptOutParameter && context?.attributes[Self.telemetryOptOutAttribute] == .bool(true)
    }
}

// MARK: - Internal methods consumed by the React Native SDK

extension FlagsClient: FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignments() -> [String: FlagAssignment]? {
        return repository.flagAssignments()
    }

    @_spi(Internal)
    public func sendFlagEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        trackEvaluation(
            key: key,
            assignment: assignment,
            context: context,
            trackEvaluationTelemetry: !isEvaluationTelemetryOptedOut(in: context)
        )
    }

    @_spi(Internal)
    public func sendFlagExposure(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        exposureLogger.logExposure(for: key, assignment: assignment, evaluationContext: context)
    }

    @_spi(Internal)
    public func sendFlagEvaluationEvent(key: String, assignment: FlagAssignment?, context: FlagsEvaluationContext, errorCode: String?) {
        guard !isEvaluationTelemetryOptedOut(in: context) else {
            return
        }

        // Hook errors can contain arbitrary customer data. Only forward standard OpenFeature codes.
        let sanitizedErrorCode: String?
        switch errorCode {
        case nil:
            sanitizedErrorCode = nil
        case EvaluationError.providerNotReady, EvaluationError.providerFatal, EvaluationError.flagNotFound,
             EvaluationError.parseError, EvaluationError.typeMismatch, EvaluationError.targetingKeyMissing,
             EvaluationError.invalidContext, EvaluationError.general:
            sanitizedErrorCode = errorCode
        default:
            sanitizedErrorCode = EvaluationError.general
        }

        evaluationLogger.logEvaluation(
            for: key,
            assignment: assignment ?? Self.defaultAssignment,
            evaluationContext: context,
            flagError: sanitizedErrorCode
        )
    }

    @_spi(Internal)
    public func sendFlagRUMEvaluation(key: String, variant: String, context: FlagsEvaluationContext) {
        guard !isEvaluationTelemetryOptedOut(in: context) else {
            return
        }
        rumFlagEvaluationReporter.sendFlagEvaluation(flagKey: key, value: variant)
    }
}

extension FlagsClient: FlagsClientFlushable {
    func flush() {
        repository.flush()
    }
}
