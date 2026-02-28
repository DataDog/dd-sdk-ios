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

    var stateManager: FlagsStateManager { get }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )

    func flagAssignment(for key: String) -> FlagAssignment?

    func flagAssignments() -> [String: FlagAssignment]?

    func reset()
}

internal final class FlagsRepository {
    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    let clientName: String
    let stateManager: FlagsStateManager

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    @ReadWriteLock
    private var flagsData: FlagsData?

    @ReadWriteLock
    private var hasReadFlagsData = false

    private let readSemaphore = DispatchSemaphore(value: 0)

    init(
        clientName: String,
        flagAssignmentsFetcher: any FlagAssignmentsFetching,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope,
        stateManager: FlagsStateManager = FlagsStateManager()
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.stateManager = stateManager
        readState()
    }

    private func readState() {
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            defer {
                // Signal on elevated queue to avoid priority inversion
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
            }
            guard let self else {
                return
            }
            self.flagsData = data
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
        guard let flagsData else {
            return
        }
        featureScope.flagsDataStore.setFlagsData(flagsData, forClientNamed: clientName)
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        return flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        return flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        return flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        waitForFlagsDataRead()
        let hadFlags = flagsData != nil
        stateManager.updateState(.reconciling)

        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            switch result {
            case .success(let flags):
                guard let self else {
                    completion(.failure(.clientNotInitialized))
                    return
                }
                self.flagsData = .init(
                    flags: flags,
                    context: context,
                    date: self.dateProvider.now
                )
                self.writeState()
                self.stateManager.updateState(.ready)
                completion(.success(()))
            case .failure(let error):
                if hadFlags {
                    self?.stateManager.updateState(.stale)
                } else {
                    self?.stateManager.updateState(.error)
                }
                completion(.failure(error))
            }
        }
    }

    func reset() {
        flagsData = nil
        stateManager.updateState(.notReady)
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
    }
}
