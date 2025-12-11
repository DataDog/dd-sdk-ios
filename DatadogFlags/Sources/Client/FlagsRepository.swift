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

    func flagAssignmentsSnapshot() -> [String: FlagAssignment]?

    func reset()
}

internal final class FlagsRepository {
    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    let clientName: String

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    @ReadWriteLock
    private var state: FlagsData?

    @ReadWriteLock
    private var hasReadFlagsData = false

    private let readSemaphore = DispatchSemaphore(value: 0)

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
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] state in
            defer {
                // Signal on elevated queue to avoid priority inversion
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
            }
            guard let self else {
                return
            }
            self.state = state
            self.hasReadFlagsData = true
        }
    }

    private func waitForFlagsDataRead() {
        guard !hasReadFlagsData else {
            return
        }
        _ = readSemaphore.wait(timeout: .now() + Constants.readTimeout)
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
        waitForFlagsDataRead()
        return state?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        return state?.flags[key]
    }

    func flagAssignmentsSnapshot() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        return state?.flags
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
