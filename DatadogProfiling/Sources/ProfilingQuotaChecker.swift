/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

internal struct ProfilingQuotaCheckResult: Equatable {
    internal enum Decision: String, Equatable {
        case quotaOK = "quota_ok"
        case quotaKO = "quota_ko"
    }

    let decision: Decision
    let reason: ProfilingContext.QuotaReason
}

internal protocol ProfilingQuotaChecking: FeatureMessageReceiver {
    var currentQuotaCheckResult: ProfilingQuotaCheckResult? { get }
}

internal final class ProfilingQuotaChecker: ProfilingQuotaChecking {
    private enum Constants {
        static let quotaPath = "/api/v2/profiling/quota"
        static let sessionIDQueryItem = "session_id"
    }

    private struct State {
        var sessionID: String?
        var currentQuotaCheckResult: ProfilingQuotaCheckResult?
        var isPending = false
    }

    private let urlSession: URLSession
    private weak var core: DatadogCoreProtocol?
    @ReadWriteLock
    private var state = State()

    init(urlSession: URLSession = ProfilingQuotaChecker.urlSession) {
        self.urlSession = urlSession
    }

    var currentQuotaCheckResult: ProfilingQuotaCheckResult? {
        state.currentQuotaCheckResult
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              let rumContext = context.additionalContext(ofType: RUMCoreContext.self) else {
            return false
        }

        self.core = core
        checkIfNeeded(sessionID: rumContext.sessionID, context: context)

        return false
    }

    func request(sessionID: String, context: DatadogContext) -> URLRequest {
        var request = URLRequest(url: Self.quotaURL(for: context.site, sessionID: sessionID))
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue(context.clientToken, forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddClientTokenHeaderField)

        return request
    }

    static func quotaURL(for site: DatadogSite, sessionID: String) -> URL {
        var components = URLComponents(url: site.endpoint, resolvingAgainstBaseURL: false)
        let quotaHost = components?.host.map { "quota.\($0)" }
        components?.host = quotaHost
        components?.path = Constants.quotaPath
        components?.queryItems = [URLQueryItem(name: Constants.sessionIDQueryItem, value: sessionID)]

        // swiftlint:disable force_unwrapping
        return components!.url!
        // swiftlint:enable force_unwrapping
    }

    static func mapResponse(
        data: Data?,
        response _: URLResponse?,
        error: Error?
    ) -> ProfilingQuotaCheckResult {
        if let error = error as? URLError {
            if error.code == .timedOut {
                return .init(decision: .quotaOK, reason: .timeout)
            }

            return .init(decision: .quotaOK, reason: .apiError)
        }

        guard
            let data,
            let quotaResponse = try? JSONDecoder().decode(QuotaResponse.self, from: data)
        else {
            return .init(decision: .quotaOK, reason: .apiError)
        }

        return map(attributes: quotaResponse.data.attributes)
    }

    static var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: configuration)
    }

    private static func map(attributes: QuotaResponse.Attributes) -> ProfilingQuotaCheckResult {
        let reason = normalizedReason(from: attributes.reason)

        switch reason {
        case .quotaExceeded, .orgDisabled:
            if attributes.admitted {
                return .init(decision: .quotaOK, reason: reason)
            } else {
                return .init(decision: .quotaKO, reason: reason)
            }
        case .quotaOk, .backendUnavailable, .undefined:
            return .init(decision: .quotaOK, reason: reason)
        case .timeout, .apiError:
            return .init(decision: .quotaOK, reason: .apiError)
        }
    }

    private static func normalizedReason(from rawValue: String?) -> ProfilingContext.QuotaReason {
        switch rawValue {
        case ProfilingContext.QuotaReason.quotaOk.rawValue:
            return .quotaOk
        case ProfilingContext.QuotaReason.quotaExceeded.rawValue:
            return .quotaExceeded
        case ProfilingContext.QuotaReason.orgDisabled.rawValue:
            return .orgDisabled
        case ProfilingContext.QuotaReason.backendUnavailable.rawValue, "backend_client_not_initialized":
            return .backendUnavailable
        case ProfilingContext.QuotaReason.undefined.rawValue:
            return .undefined
        default:
            return .undefined
        }
    }

    private func checkIfNeeded(sessionID: String, context: DatadogContext) {
        var shouldStartRequest = false
        var shouldResetQuotaReason = false

        _state.mutate {
            if $0.sessionID != sessionID {
                $0.sessionID = sessionID
                $0.currentQuotaCheckResult = nil
                $0.isPending = true
                shouldStartRequest = true
                shouldResetQuotaReason = true
            } else if $0.currentQuotaCheckResult == nil && $0.isPending == false {
                $0.isPending = true
                shouldStartRequest = true
            }
        }

        guard shouldStartRequest else {
            return
        }

        if shouldResetQuotaReason {
            updateProfilingContext(with: nil)
        }

        let request = self.request(sessionID: sessionID, context: context)

        urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }

            let result = Self.mapResponse(data: data, response: response, error: error)

            if self.store(result: result, sessionID: sessionID) {
                self.updateProfilingContext(with: result.reason)
            }
        }
        .resume()
    }

    private func store(result: ProfilingQuotaCheckResult, sessionID: String) -> Bool {
        var didStore = false

        _state.mutate {
            guard $0.sessionID == sessionID else {
                return
            }

            $0.currentQuotaCheckResult = result
            $0.isPending = false
            didStore = true
        }

        return didStore
    }

    private func updateProfilingContext(with quotaReason: ProfilingContext.QuotaReason?) {
        guard let core else {
            return
        }

        core.set(context: ProfilingContext(status: .current, quotaReason: quotaReason))
    }
}

private struct QuotaResponse: Decodable {
    struct DataContainer: Decodable {
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let admitted: Bool
        let reason: String?
    }

    let data: DataContainer
}

#endif
