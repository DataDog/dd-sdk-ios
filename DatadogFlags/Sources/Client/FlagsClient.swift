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
    /// The default client name used when no name is specified.
    ///
    /// Use this constant when you need to reference the default client by name.
    public static let defaultName = "default"

    private let repository: any FlagsRepositoryProtocol
    private let exposureLogger: any ExposureLogging
    private let rumFlagEvaluationReporter: any RUMFlagEvaluationReporting

    internal init(
        repository: any FlagsRepositoryProtocol,
        exposureLogger: any ExposureLogging,
        rumFlagEvaluationReporter: any RUMFlagEvaluationReporting
    ) {
        self.repository = repository
        self.exposureLogger = exposureLogger
        self.rumFlagEvaluationReporter = rumFlagEvaluationReporter
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
        // To ensure the correct registration order between Core and Features,
        // the entire initialization flow is synchronized on the main thread.
        runOnMainThreadSync {
            doCreate(name: name, in: core)
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
                featureScope: featureScope
            ),
            exposureLogger: feature.makeExposureLogger(featureScope),
            rumFlagEvaluationReporter: feature.makeRUMFlagEvaluationReporter(featureScope)
        )

        feature.clientRegistry.register(client, named: name)
        return client
    }
}

extension FlagsClient: FlagsClientProtocol {
    public func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        repository.setEvaluationContext(context, completion: completion)
    }

    public func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        guard let flagAssignment = repository.flagAssignment(for: key) else {
            return FlagDetails(key: key, value: defaultValue, error: .flagNotFound)
        }

        guard let value = flagAssignment.variation(as: T.self) else {
            return FlagDetails(key: key, value: defaultValue, error: .typeMismatch)
        }

        let details = FlagDetails(
            key: key,
            value: value,
            variant: flagAssignment.variationKey,
            reason: flagAssignment.reason
        )

        if let context = repository.context {
            trackEvaluation(key: key, assignment: flagAssignment, value: value, context: context)
        }

        return details
    }

    internal func trackEvaluation(key: String, assignment: FlagAssignment, value: FlagValue, context: FlagsEvaluationContext) {
        exposureLogger.logExposure(
            for: key,
            assignment: assignment,
            evaluationContext: context
        )

        rumFlagEvaluationReporter.sendFlagEvaluation(
            flagKey: key,
            value: value
        )
    }
}

// MARK: - Internal methods consumed by the React Native SDK

extension FlagsClient: FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignments() -> [String: FlagAssignment]? {
        return repository.flagAssignmentsSnapshot()
    }

    @_spi(Internal)
    public func sendFlagEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        var value: FlagValue
        switch assignment.variation {
        case .boolean(let v): value = v
        case .string(let v): value = v
        case .integer(let v): value = v
        case .double(let v): value = v
        case .object(let v): value = v
        case .unknown: value = AnyValue.null
        }

        trackEvaluation(key: key, assignment: assignment, value: value, context: context)
    }
}
