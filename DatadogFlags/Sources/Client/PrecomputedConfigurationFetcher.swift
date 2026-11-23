/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A precomputed configuration detached from any client.
///
/// It carries the same data as the `precomputed` entry of the portable configuration string: the raw `response`
/// body, the `context` it was computed for, `fetchedAt` in milliseconds since epoch, and the optional `etag`.
/// `assignments` is `response` decoded once. `context` never contains the assignment authorization token, so the
/// configuration is safe to store.
internal struct FetchedPrecomputedConfiguration: Equatable {
    let response: String
    let context: FlagsEvaluationContext
    let fetchedAt: Double
    let etag: String?
    let assignments: FlagAssignmentsResponse
}

/// Fetches precomputed assignments for one context and returns them as a detached configuration.
///
/// It reuses the request and response code of `FlagsClient`, but it does not read or change any client state,
/// repository, cache or listener. The caller decides what to do with the result.
internal final class PrecomputedConfigurationFetcher {
    private let fetcher: FlagAssignmentsFetcher
    private let experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode
    private let dateProvider: any DateProvider
    /// `FlagsRequestDiagnostics` is not thread-safe, and callers may fetch from several threads.
    @ReadWriteLock
    private var requestDiagnostics: FlagsRequestDiagnostics

    init(
        fetcher: FlagAssignmentsFetcher,
        experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode = .disabled,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.fetcher = fetcher
        self.experimentationOptOutMode = experimentationOptOutMode
        self.dateProvider = dateProvider
        self.requestDiagnostics = FlagsRequestDiagnostics(now: dateProvider.now)
    }

    /// Fetches the configuration for `context`. The completion runs on a background queue.
    func fetch(
        for context: FlagsEvaluationContext,
        completion: @escaping (Result<FetchedPrecomputedConfiguration, FlagsError>) -> Void
    ) {
        let authorization = context.extractingAssignmentAuthorization()
        let targetingContext = authorization.context
        if authorization.shouldWarn {
            DD.logger.warn(AssignmentAuthorization.unusableTokenWarning)
        }
        let policy: ExperimentationOptOut?
        do {
            policy = try targetingContext.experimentationOptOut(mode: experimentationOptOutMode)
        } catch {
            // Keep validation completions off the caller's stack, consistent with fetch completions.
            DispatchQueue.global(qos: .utility).async { completion(.failure(.invalidContext)) }
            return
        }
        var diagnostics: FlagsRequestDiagnostics.Snapshot?
        _requestDiagnostics.mutate { diagnostics = $0.accept() }
        // Taken before the request, like the browser SDK, so the value never overstates freshness.
        let fetchedAt = dateProvider.now.timeIntervalSince1970 * 1_000

        fetcher.fetchedFlagAssignments(
            for: targetingContext,
            experimentationOptOut: policy,
            diagnostics: diagnostics,
            assignmentToken: authorization.token
        ) { result in
            completion(result.flatMap { fetched in
                guard let body = String(data: fetched.body, encoding: .utf8) else {
                    return .failure(.invalidResponse)
                }
                return .success(
                    FetchedPrecomputedConfiguration(
                        response: body,
                        context: targetingContext,
                        fetchedAt: fetchedAt,
                        etag: fetched.etag,
                        assignments: fetched.response
                    )
                )
            })
        }
    }
}
