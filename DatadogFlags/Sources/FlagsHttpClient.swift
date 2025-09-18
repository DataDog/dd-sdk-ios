/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol FlagsHttpClient {
    func postPrecomputeAssignments(
        context: FlagsEvaluationContext, 
        configuration: FlagsClientConfiguration, 
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    )
}

internal class NetworkFlagsHttpClient: FlagsHttpClient {
    
    func postPrecomputeAssignments(
        context: FlagsEvaluationContext, 
        configuration: FlagsClientConfiguration, 
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    ) {
        let endpointURL: String
        
        // Determine endpoint URL based on configuration priority
        if let flaggingProxy = configuration.flaggingProxy {
            // Use flagging proxy if provided
            if flaggingProxy.hasPrefix("http://") || flaggingProxy.hasPrefix("https://") {
                endpointURL = flaggingProxy
            } else {
                endpointURL = "https://\(flaggingProxy)"
            }
        } else if let baseURL = configuration.baseURL {
            // Use explicit baseURL if provided
            endpointURL = "\(baseURL)/precompute-assignments"
        } else {
            // Build endpoint using site configuration
            do {
                let customerDomain = FlagsEndpointBuilder.extractCustomerDomain(from: configuration.clientToken)
                endpointURL = try FlagsEndpointBuilder.buildEndpointURL(
                    site: configuration.site,
                    customerDomain: customerDomain
                )
            } catch {
                completion(.failure(error))
                return
            }
        }
        
        guard let url = URL(string: endpointURL) else {
            completion(.failure(FlagsError.invalidConfiguration))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Build headers
        var headers = [String: String]()
        headers["Content-Type"] = "application/vnd.api+json"
        headers["dd-client-token"] = configuration.clientToken
        
        // Add application ID header if provided
        if let applicationId = configuration.applicationId {
            headers["dd-application-id"] = applicationId
        }
        
        // Add custom headers
        for (key, value) in configuration.customHeaders {
            headers[key] = value
        }
        
        // Set headers on request
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // Serialize context attributes (stringify non-string values like JavaScript client)
        let stringifiedAttributes: [String: String] = context.attributes.mapValues { value in
            if let stringValue = value as? String {
                return stringValue
            } else {
                // JSON serialize non-string values
                if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
                   let jsonString = String(data: data, encoding: .utf8) {
                    return jsonString
                } else {
                    return String(describing: value)
                }
            }
        }
        
        let requestBody: [String: Any] = [
            "data": [
                "type": "precompute-assignments-request",
                "attributes": [
                    "env": [
                        "name": configuration.environment,
                        "dd_env": configuration.environment
                    ],
                    "subject": [
                        "targeting_key": context.targetingKey,
                        "targeting_attributes": stringifiedAttributes
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let response = response else {
                completion(.failure(FlagsError.invalidResponse))
                return
            }
            
            completion(.success((data, response)))
        }.resume()
    }
}