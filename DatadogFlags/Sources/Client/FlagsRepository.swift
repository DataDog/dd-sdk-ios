/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagsRepositoryProtocol {
    var clientName: String { get }

    var context: FlagsEvaluationContext? { get }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )

    func flagAssignment(for key: String) -> FlagAssignment?

    func reset()
}

internal final class FlagsRepository {
    let clientName: String

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    @ReadWriteLock
    private var state: FlagsData?

    init(
        clientName: String,
        flagAssignmentsFetcher: any FlagAssignmentsFetching,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        readState()
    }

    private func readState() {
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { state in
            self.state = state
        }
    }

    private func writeState() {
        guard let state else {
            return
        }
        featureScope.flagsDataStore.setFlagsData(state, forClientNamed: clientName)
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var context: FlagsEvaluationContext? {
        state?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        state?.flags[key]
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            switch result {
            case .success(let flags):
                guard let self else {
                    completion(.failure(.clientNotInitialized))
                    return
                }
                self.state = .init(
                    flags: flags,
                    context: context,
                    date: self.dateProvider.now
                )
                self.writeState()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func reset() {
        state = nil
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
    }
}
