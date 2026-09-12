/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

internal struct ProfilingQuotaResult: Equatable, Sendable {
    internal enum Decision: Equatable, Sendable {
        case quotaOK
        case quotaKO
    }

    let decision: Decision
    private let reasonRawValue: String

    var reason: DDProfiling.QuotaReason {
        DDProfiling.QuotaReason(rawValue: reasonRawValue) ?? .undefined
    }

    init(decision: Decision, reason: DDProfiling.QuotaReason) {
        self.decision = decision
        self.reasonRawValue = reason.rawValue
    }
}

internal typealias ProfilingQuotaResultListener = @Sendable (ProfilingQuotaResult?) -> Void

internal protocol ProfilingQuotaChecking: AnyObject, FeatureMessageReceiver {
    var quotaResult: ProfilingQuotaResult? { get }

    /// Called when the active session quota result changes.
    ///
    /// The callback emits `nil` when a new session starts and the previous result is cleared,
    /// then emits the resolved result once the quota request completes.
    var onQuotaResultUpdate: ProfilingQuotaResultListener? { get set }
}

extension ProfilingQuotaChecking {
    // Keep quota fail-open while the check is pending. This avoids losing early profiles on slow quota responses.
    var isRejectedByQuota: Bool {
        quotaResult?.decision == .quotaKO
    }
}

/// Checks profiling quota admission for the active RUM session.
///
/// This service owns the quota request lifecycle and session-scoped result cache.
/// It starts a quota request when a sampled-in RUM session id is observed with granted
/// tracking consent, ignores stale responses for previous sessions and fails open
/// on request or decoding errors.
internal final class ProfilingQuotaChecker: ProfilingQuotaChecking, Sendable {
    private enum Constants {
        static let quotaPath = "/api/v2/profiling/quota"
        static let sessionIDQueryItem = "session_id"
    }

    private static var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: configuration)
    }

    private let urlSession: URLSession
    private let state = ReadWriteLock(wrappedValue: State.idle)
    private let quotaResultUpdate = ReadWriteLock<ProfilingQuotaResultListener?>(wrappedValue: nil)

    var quotaResult: ProfilingQuotaResult? { state.wrappedValue.quotaResult }

    var onQuotaResultUpdate: ProfilingQuotaResultListener? {
        get { quotaResultUpdate.wrappedValue }
        set { quotaResultUpdate.wrappedValue = newValue }
    }

    init(urlSession: URLSession = ProfilingQuotaChecker.urlSession) {
        self.urlSession = urlSession
    }
}

extension ProfilingQuotaChecker: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              context.trackingConsent == .granted,
              let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
              rumContext.sessionSampler.isSampled else {
            return false
        }

        checkIfNeeded(sessionID: rumContext.sessionID, context: context)

        return false
    }

    private func checkIfNeeded(sessionID: String, context: DatadogContext) {
        var shouldStartRequest = false

        state.mutate {
            switch $0 {
            case .idle:
                $0 = .pending(sessionID: sessionID)
                shouldStartRequest = true
            case .pending(let currentSessionID), .resolved(let currentSessionID, _):
                guard currentSessionID != sessionID else {
                    return
                }

                $0 = .pending(sessionID: sessionID)
                shouldStartRequest = true
            }
        }

        guard shouldStartRequest else {
            return
        }

        onQuotaResultUpdate?(nil)

        let request = self.request(sessionID: sessionID, context: context)
        urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }

            let result = Self.mapResponse(data: data, response: response, error: error)

            if self.storeIfCurrentSession(result: result, sessionID: sessionID) {
                self.onQuotaResultUpdate?(result)
            }
        }
        .resume()
    }

    private func request(sessionID: String, context: DatadogContext) -> URLRequest {
        var request = URLRequest(url: quotaURL(for: context.site, sessionID: sessionID))
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue(context.clientToken, forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddClientTokenHeaderField)

        return request
    }

    private func quotaURL(for site: DatadogSite, sessionID: String) -> URL {
        var components = URLComponents(url: site.endpoint, resolvingAgainstBaseURL: false)
        let quotaHost = components?.host.map { "quota.\($0)" }
        components?.host = quotaHost
        components?.path = Constants.quotaPath
        components?.queryItems = [URLQueryItem(name: Constants.sessionIDQueryItem, value: sessionID)]

        return components?.url ?? site.endpoint
    }

    private func storeIfCurrentSession(result: ProfilingQuotaResult, sessionID: String) -> Bool {
        var didStore = false

        state.mutate {
            switch $0 {
            case .pending(let currentSessionID) where currentSessionID == sessionID,
                    .resolved(let currentSessionID, _) where currentSessionID == sessionID:
                $0 = .resolved(sessionID: sessionID, result: result)
                didStore = true
            default:
                return
            }
        }

        return didStore
    }
}

extension ProfilingQuotaChecker {
    static func mapResponse(data: Data?, response _: URLResponse?, error: Error?) -> ProfilingQuotaResult {
        if let error = error as? URLError {
            if error.code == .timedOut {
                return .init(decision: .quotaOK, reason: .timeout)
            }

            return .init(decision: .quotaOK, reason: .apiError)
        }

        guard let data,
              let quotaResponse = try? JSONDecoder().decode(QuotaResponse.self, from: data)
        else {
            return .init(decision: .quotaOK, reason: .apiError)
        }

        return quotaResponse.data.attributes.quotaResult
    }
}

private extension ProfilingQuotaChecker {
    enum State {
        case idle
        case pending(sessionID: String)
        case resolved(sessionID: String, result: ProfilingQuotaResult)

        var quotaResult: ProfilingQuotaResult? {
            guard case let .resolved(_, result) = self else {
                return nil
            }

            return result
        }
    }
}

private struct QuotaResponse: Decodable {
    struct DataContainer: Decodable {
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let admitted: Bool
        let reason: DDProfiling.QuotaReason

        enum CodingKeys: String, CodingKey {
            case admitted
            case reason
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            admitted = try container.decode(Bool.self, forKey: .admitted)

            let rawReason = try container.decodeIfPresent(String.self, forKey: .reason)
            reason = Self.normalizedReason(from: rawReason)
        }

        private static func normalizedReason(from rawValue: String?) -> DDProfiling.QuotaReason {
            switch rawValue {
            case DDProfiling.QuotaReason.backendUnavailable.rawValue, "backend_client_not_initialized":
                return .backendUnavailable
            case let rawValue:
                return rawValue.flatMap(DDProfiling.QuotaReason.init(rawValue:)) ?? .undefined
            }
        }
    }

    let data: DataContainer
}

private extension QuotaResponse.Attributes {
    /// Converts quota response attributes into the session-scoped upload gate.
    ///
    /// `admitted` is the source of truth for quota admission/rejection reasons. This keeps
    /// the SDK correct if `admitted` and `reason` disagree, or if a new backend rejection
    /// reason is normalized to `.undefined`. Explicit fail-open reasons keep uploads enabled
    /// regardless of `admitted`.
    var quotaResult: ProfilingQuotaResult {
        let decision: ProfilingQuotaResult.Decision
        switch reason {
        case .backendUnavailable, .timeout, .apiError:
            decision = .quotaOK
        case .quotaOk, .quotaExceeded, .orgDisabled, .undefined:
            decision = admitted ? .quotaOK : .quotaKO
        @unknown default:
            decision = admitted ? .quotaOK : .quotaKO
        }

        return .init(decision: decision, reason: reason)
    }
}

#endif
