/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A non-functional implementation of FlagsClient that does nothing.
/// Used as a safe fallback when FlagsClient creation fails.
internal class NOPFlagsClient: FlagsClient {
    override internal init(configuration: FlagsClient.Configuration, httpClient: FlagsHTTPClient, store: FlagsStore, featureScope: FeatureScope) {
        super.init(configuration: configuration, httpClient: httpClient, store: store, featureScope: featureScope)
    }

    internal convenience init() {
        let configuration = FlagsClient.Configuration()
        let httpClient = NOPFlagsHTTPClient()
        let store = NOPFlagsStore()
        let featureScope = NOPFeatureScope()
        self.init(configuration: configuration, httpClient: httpClient, store: store, featureScope: featureScope)
    }

    override internal func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {
        completion(.failure(.clientNotInitialized))
    }

    override internal func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        return defaultValue
    }

    override internal func getStringValue(key: String, defaultValue: String) -> String {
        return defaultValue
    }

    override internal func getIntegerValue(key: String, defaultValue: Int64) -> Int64 {
        return defaultValue
    }

    override internal func getDoubleValue(key: String, defaultValue: Double) -> Double {
        return defaultValue
    }

    override internal func getObjectValue(key: String, defaultValue: [String: Any]) -> [String: Any] {
        return defaultValue
    }
}

/// No-operation implementation of FlagsHTTPClient
internal class NOPFlagsHTTPClient: FlagsHTTPClient {
    func postPrecomputeAssignments(context: FlagsEvaluationContext, configuration: FlagsClient.Configuration, sdkContext: DatadogContext, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        completion(.failure(FlagsError.clientNotInitialized))
    }
}

/// No-operation implementation of FlagsStore
internal class NOPFlagsStore: FlagsStore {
    override internal init(featureScope: FeatureScope, instanceName: String) {
        super.init(featureScope: featureScope, instanceName: instanceName)
    }

    internal convenience init() {
        self.init(featureScope: NOPFeatureScope(), instanceName: FlagsClientRegistry.defaultInstanceName)
    }

    override internal func setFlags(_ flags: [String: Any], context: FlagsEvaluationContext?) {
        // No-op
    }

    override internal func getFlags() -> [String: Any] {
        return [:]
    }
}
