/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class FlagsClient {
    private let configuration: FlagsClientConfiguration
    private let httpClient: FlagsHttpClient
    private let store: FlagsStore
    
    internal init(configuration: FlagsClientConfiguration, httpClient: FlagsHttpClient, store: FlagsStore) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.store = store
    }
    
    public static func create(with configuration: FlagsClientConfiguration) -> FlagsClient {
        let httpClient = NetworkFlagsHttpClient()
        let store = FlagsStore()
        return FlagsClient(configuration: configuration, httpClient: httpClient, store: store)
    }
    
    public func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {
        httpClient.postPrecomputeAssignments(
            context: context,
            configuration: configuration
        ) { [weak self] result in
            guard let self = self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            
            switch result {
            case .success(let (data, response)):
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    completion(.failure(.invalidResponse))
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    if let responseData = json?["data"] as? [String: Any],
                       let attributes = responseData["attributes"] as? [String: Any],
                       let flags = attributes["flags"] as? [String: Any] {
                        self.store.setFlags(flags, context: context)
                        completion(.success(()))
                    } else {
                        completion(.failure(.invalidResponse))
                    }
                } catch {
                    completion(.failure(.networkError(error)))
                }
                
            case .failure(let error):
                completion(.failure(.networkError(error)))
            }
        }
    }
    
    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? Bool {
            return value
        }
        return defaultValue
    }
    
    public func getStringValue(key: String, defaultValue: String) -> String {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? String {
            return value
        }
        return defaultValue
    }
    
    public func getIntegerValue(key: String, defaultValue: Int64) -> Int64 {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? NSNumber {
            return value.int64Value
        }
        return defaultValue
    }
    
    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? NSNumber {
            return value.doubleValue
        }
        return defaultValue
    }
    
    public func getObjectValue(key: String, defaultValue: [String: Any]) -> [String: Any] {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? [String: Any] {
            return value
        }
        return defaultValue
    }
}
