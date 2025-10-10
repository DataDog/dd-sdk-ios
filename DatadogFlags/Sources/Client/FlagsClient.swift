/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FlagsClient {
    public static let defaultName = "default"

    private let repository: any FlagsRepositoryProtocol
    private let exposureLogger: any ExposureLogging
    private let rumExposureLogger: any RUMExposureLogging

    internal init(
        repository: any FlagsRepositoryProtocol,
        exposureLogger: any ExposureLogging,
        rumExposureLogger: any RUMExposureLogging
    ) {
        self.repository = repository
        self.exposureLogger = exposureLogger
        self.rumExposureLogger = rumExposureLogger
    }

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
            rumExposureLogger: feature.makeRUMExposureLogger(featureScope)
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
            exposureLogger.logExposure(
                for: key,
                assignment: flagAssignment,
                evaluationContext: context
            )
            rumExposureLogger.logExposure(
                flagKey: key,
                value: value,
                assignment: flagAssignment,
                evaluationContext: context
            )
        }

        return details
    }
}
