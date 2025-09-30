/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagsRepositoryProtocol {
    var context: FlagsEvaluationContext? { get }

    func flagAssignment(for key: String) -> FlagAssignment?

    func setFlagAssignments(
        _ flags: [String: FlagAssignment],
        for context: FlagsEvaluationContext,
        date: Date
    )

    func reset()
}

internal final class FlagsRepository {
    private let clientName: String
    private let featureScope: any FeatureScope

    @ReadWriteLock
    private var state: FlagsData?

    init(clientName: String, featureScope: any FeatureScope) {
        self.clientName = clientName
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

    func setFlagAssignments(
        _ flags: [String: FlagAssignment],
        for context: FlagsEvaluationContext,
        date: Date
    ) {
        state = .init(flags: flags, context: context, date: date)
        writeState()
    }

    func reset() {
        state = nil
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
    }
}
