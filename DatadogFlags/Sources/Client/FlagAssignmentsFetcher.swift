/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagAssignmentsFetching {
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
        assignmentToken: String?,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    )
}

extension FlagAssignmentsFetching {
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        flagAssignments(
            for: evaluationContext,
            experimentationOptOut: nil,
            diagnostics: nil,
            assignmentToken: nil,
            completion: completion
        )
    }
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?
    let flagSelection: CanonicalFlagSelection?

    private let featureScope: any FeatureScope
    private let assignmentFetchQueue: DispatchQueue
    private let fetch: (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void

    private static let decoder = JSONDecoder()
    private static let flagSelectionIgnoredHeader = "DD-Flag-Selection-Ignored"
    // The reasons the server sends in `DD-Flag-Selection-Ignored`. Any other value, for example one set by a proxy
    // behind `customFlagsEndpoint`, is reported as `unknown`, so header content never reaches logs or telemetry.
    private static let flagSelectionIgnoredReasons = [
        "malformed_selection", "too_many_values", "invalid_key_pattern", "invalid_tag", "tag_load_failed"
    ]
    private static let unknownFlagSelectionIgnoredReason = "unknown"
    private static let redactedFlagSelectionIgnoredReason = "redacted"
    // The longest known reason is 19 bytes, so a longer value is reported as `unknown` without a lookup.
    private static let maxFlagSelectionIgnoredReasonBytes = 32

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
        featureScope: any FeatureScope
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let urlSession = URLSession(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            flagSelection: flagSelection,
            featureScope: featureScope,
            fetch: urlSession.fetch
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
        featureScope: any FeatureScope,
        assignmentFetchQueue: DispatchQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-flags-assignment-fetch",
            qos: .utility,
            autoreleaseFrequency: .workItem
        ),
        fetch: @escaping (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.flagSelection = flagSelection
        self.featureScope = featureScope
        self.assignmentFetchQueue = assignmentFetchQueue
        self.fetch = fetch
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot? = nil,
        assignmentToken: String? = nil,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        let authorization = evaluationContext.extractingAssignmentAuthorization()
        let evaluationContext = authorization.context
        let suppliedToken = assignmentToken ?? authorization.token
        let assignmentToken = AssignmentAuthorization.usableToken(suppliedToken)
        if authorization.shouldWarn || (suppliedToken?.isEmpty == false && assignmentToken == nil) {
            DD.logger.warn(AssignmentAuthorization.unusableTokenWarning)
        }
        // Repository callbacks can invoke application code; keep them off shared SDK work queues.
        let completion: (Result<FlagAssignmentsResponse, FlagsError>) -> Void = { result in
            DispatchQueue.global(qos: .utility).async {
                completion(result)
            }
        }
        featureScope.context { [weak self] context in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            self.assignmentFetchQueue.async {
                self.fetchAssignments(
                    for: evaluationContext,
                    experimentationOptOut: experimentationOptOut,
                    diagnostics: diagnostics,
                    assignmentToken: assignmentToken,
                    context: context,
                    completion: completion
                )
            }
        }
    }

    private func fetchAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
        assignmentToken: String?,
        context: DatadogContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        do {
            let request = try URLRequest.flagAssignmentsRequest(
                url: url(with: context),
                evaluationContext: evaluationContext,
                context: context,
                // Custom headers can carry proxy credentials, so only the custom endpoint receives them.
                customHeaders: customEndpoint != nil ? customHeaders : nil,
                flagSelection: flagSelection,
                experimentationOptOut: experimentationOptOut,
                diagnostics: diagnostics,
                assignmentToken: assignmentToken
            )
            fetch(request) { [assignmentFetchQueue, featureScope, flagSelection] result in
                assignmentFetchQueue.async {
                    Self.handleFetchResult(
                        result,
                        experimentationOptOut: experimentationOptOut,
                        supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                        requestCarriedFlagSelection: flagSelection != nil,
                        requestCarriedAssignmentToken: assignmentToken != nil,
                        featureScope: featureScope,
                        completion: completion
                    )
                }
            }
        } catch let error {
            DD.logger.error("Failed to encode flag assignments request body.", error: error)
            featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
            completion(.failure(.invalidConfiguration))
        }
    }

    /// Returns the reason to report for a `DD-Flag-Selection-Ignored` value, or `nil` when the header is absent or empty.
    /// Values are compared on bytes, case-sensitively and without trimming.
    private static func reportedFlagSelectionIgnoredReason(_ value: String?, redact: Bool) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        guard !redact else {
            return redactedFlagSelectionIgnoredReason
        }
        guard value.utf8.count <= maxFlagSelectionIgnoredReasonBytes,
              let reason = flagSelectionIgnoredReasons.first(where: { $0.utf8.elementsEqual(value.utf8) }) else {
            return unknownFlagSelectionIgnoredReason
        }
        return reason
    }

    private static func handleFetchResult(
        _ result: Result<(Data, HTTPURLResponse), Error>,
        experimentationOptOut: ExperimentationOptOut?,
        supportsObfuscation: Bool,
        requestCarriedFlagSelection: Bool,
        requestCarriedAssignmentToken: Bool,
        featureScope: any FeatureScope,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        switch result {
        case let .success((data, httpResponse)):
            let ignoredReason = requestCarriedFlagSelection
                ? reportedFlagSelectionIgnoredReason(
                    httpResponse.value(forHTTPHeaderField: flagSelectionIgnoredHeader),
                    redact: requestCarriedAssignmentToken
                )
                : nil
            if httpResponse.statusCode == 401, isAssignmentAuthorizationRejection(data) {
                DD.logger.warn("Assignment download failed: \(AssignmentAuthorization.rejectionCode)")
                completion(.failure(.assignmentAuthorizationFailed))
                return
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                let error = URLError(.badServerResponse)
                if requestCarriedAssignmentToken {
                    DD.logger.warn("Failed to fetch flag assignments from the server.")
                } else {
                    DD.logger.warn("Failed to fetch flag assignments from the server.", error: error)
                }
                completion(.failure(.networkError(error)))
                return
            }
            do {
                let response = try decoder.decode(FlagAssignmentsResponse.self, from: data)
                guard response.obfuscation == nil || supportsObfuscation else {
                    throw FlagsError.invalidResponse
                }

                guard ExperimentationOptOut.accepts(response, for: experimentationOptOut) else {
                    throw FlagsError.invalidResponse
                }

                // Report an ignored selection only once the full configuration is accepted.
                if let ignoredReason {
                    DD.logger.error("`Flags.Configuration.flagSelection` was ignored by the server (\(ignoredReason)). Loaded the full flag configuration.")
                    // One id per reason: telemetry drops a repeated id within a session, so a shared id would hide later reasons.
                    featureScope.telemetry.debug(
                        id: "flags:selection-ignored:\(ignoredReason)",
                        message: "Flag selection ignored",
                        attributes: ["reason": ignoredReason]
                    )
                }

                // Log any flags that failed to decode to telemetry
                if !response.failedFlags.isEmpty {
                    for (flagKey, errorDescription) in response.failedFlags {
                        if requestCarriedAssignmentToken {
                            // Do not reflect server-controlled response details when a credential was sent.
                            let message = "Failed to decode a flag from flag assignments response"
                            DD.logger.warn("\(message). Flag will be dropped from configuration.")
                            featureScope.telemetry.debug(message)
                        } else {
                            let message = "Failed to decode flag '\(flagKey)' from flag assignments response"
                            let error = InternalError(description: errorDescription)
                            DD.logger.warn("\(message). Flag will be dropped from configuration.", error: error)
                            featureScope.telemetry.debug(
                                message,
                                attributes: ["flagKey": flagKey, "errorDescription": errorDescription]
                            )
                        }
                    }
                }

                completion(.success(response))
            } catch {
                let message = "Failed to decode \(FlagAssignmentsResponse.self) from flag assignments response"
                if requestCarriedAssignmentToken {
                    DD.logger.error(message)
                    featureScope.telemetry.error(message)
                } else {
                    featureScope.telemetry.error(message, error: error)
                }
                completion(.failure(.invalidResponse))
            }
        case .failure(let error):
            // The repository handles fetch failures through its error or stale state.
            if requestCarriedAssignmentToken {
                DD.logger.warn("Failed to fetch flag assignments from the server.")
                completion(.failure(.networkError(sanitizedTransportError(error))))
            } else {
                DD.logger.warn("Failed to fetch flag assignments from the server.", error: error)
                completion(.failure(.networkError(error)))
            }
        }
    }

    private static func isAssignmentAuthorizationRejection(_ data: Data) -> Bool {
        guard let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let errors = document["errors"] as? [Any] else {
            return false
        }
        // An unrelated or malformed sibling must not hide a typed rejection.
        return errors.contains { error in
            (error as? [String: Any])?["code"] as? String == AssignmentAuthorization.rejectionCode
        }
    }

    private static func sanitizedTransportError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return URLError(.unknown)
        }
        // Keep the platform classification, but discard request/response details in userInfo.
        return URLError(urlError.code)
    }

    private func url(with context: DatadogContext) -> URL {
        customEndpoint ?? context.site.flagsEndpoint().appendingPathComponent("precompute-assignments")
    }
}

extension DatadogSite {
    internal func flagsEndpoint(subdomain: String = "preview") -> URL {
        switch self {
        // swiftlint:disable force_unwrapping
        case .us1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        case .us3: return URL(string: "https://\(subdomain).ff-cdn.us3.datadoghq.com")!
        case .us5: return URL(string: "https://\(subdomain).ff-cdn.us5.datadoghq.com")!
        case .eu1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.eu")!
        case .ap1: return URL(string: "https://\(subdomain).ff-cdn.ap1.datadoghq.com")!
        case .ap2: return URL(string: "https://\(subdomain).ff-cdn.ap2.datadoghq.com")!
        case .uk1: return URL(string: "https://\(subdomain).ff-cdn.uk1.datadoghq.com")!
        case .us1_fed, .us2_fed:
            DD.logger.warn(
                """
                Government sites (us1_fed, us2_fed) are not officially supported for feature flags. \
                Falling back to us1 endpoint.
                """
            )
            return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        // swiftlint:enable force_unwrapping
        }
    }
}

extension URLSession {
    internal func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void
    ) {
        let task = self.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            completion(.success((data, httpResponse)))
        }
        if request.value(forHTTPHeaderField: AssignmentAuthorization.header) != nil {
            // Bind this policy to the original request, before URLSession can rewrite a POST
            // or remove headers while redirecting. Tokenless tasks retain URLSession's defaults.
            task.delegate = AssignmentTokenRedirectDelegate()
        }
        task.resume()
    }
}

private final class AssignmentTokenRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return the original 3xx response to the existing download-failure/fallback path.
        // Refuse every destination, including another path, hostname, port, or scheme.
        completionHandler(nil)
    }
}
