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
    private let enableExposureLogging: Bool
    private let enableRUMIntegration: Bool

    internal init(
        repository: any FlagsRepositoryProtocol,
        exposureLogger: any ExposureLogging,
        rumExposureLogger: any RUMExposureLogging,
        enableExposureLogging: Bool,
        enableRUMIntegration: Bool
    ) {
        self.repository = repository
        self.exposureLogger = exposureLogger
        self.rumExposureLogger = rumExposureLogger
        self.enableExposureLogging = enableExposureLogging
        self.enableRUMIntegration = enableRUMIntegration
    }

    @discardableResult
    public static func create(
        name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            return try runOnMainThreadSync {
                try createOrThrow(name: name, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
            return NOPFlagsClient()
        }
    }

    public static func instance(
        named name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        do {
            guard let clientRegistry = core.get(feature: FlagsFeature.self)?.clientRegistry else {
                throw ProgrammerError(
                    description: "Flags feature must be enabled before calling `FlagsClient.instance(named:in:)`."
                )
            }
            guard let client = clientRegistry.client(named: name) else {
                throw ProgrammerError(
                    description: "Flags client '\(name)' not found. Make sure that you call `FlagsClient.create(name:with:in:)` first."
                )
            }
            return client
        } catch let error {
            consolePrint("\(error)", .error)
            return NOPFlagsClient()
        }
    }

    internal static func createOrThrow(
        name: String,
        in core: DatadogCoreProtocol
    ) throws -> FlagsClientProtocol {
        guard let feature = core.get(feature: FlagsFeature.self) else {
            throw ProgrammerError(
                description: "Flags feature must be enabled before calling `FlagsClient.create(name:with:in:)`."
            )
        }
        guard !feature.clientRegistry.isRegistered(clientName: name) else {
            throw ProgrammerError(
                description: "A flags client named '\(name)' already exists."
            )
        }

        let featureScope = core.scope(for: FlagsFeature.self)
        let dateProvider = SystemDateProvider()
        let client = FlagsClient(
            repository: FlagsRepository(
                clientName: name,
                flagAssignmentsFetcher: feature.flagAssignmentsFetcher,
                dateProvider: dateProvider,
                featureScope: featureScope
            ),
            exposureLogger: ExposureLogger(
                dateProvider: dateProvider,
                featureScope: featureScope
            ),
            rumExposureLogger: RUMExposureLogger(
                dateProvider: dateProvider,
                featureScope: featureScope
            ),
            enableExposureLogging: feature.enableExposureLogging,
            enableRUMIntegration: feature.enableRUMIntegration
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
            if enableExposureLogging {
                exposureLogger.logExposure(
                    for: key,
                    assignment: flagAssignment,
                    evaluationContext: context
                )
            }
            if enableRUMIntegration {
                rumExposureLogger.logExposure(
                    flagKey: key,
                    value: value,
                    assignment: flagAssignment,
                    evaluationContext: context
                )
            }
        }

        return details
    }
}
