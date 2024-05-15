/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class FatalAppHangsHandler {
    /// RUM feature scope.
    private let featureScope: FeatureScope
    /// RUM context for fatal App Hangs monitoring.
    private let fatalErrorContext: FatalErrorContextNotifier
    /// An ID of the current process.
    private let processID: UUID
    /// Device date provider.
    private let dateProvider: DateProvider

    init(
        featureScope: FeatureScope,
        fatalErrorContext: FatalErrorContextNotifier,
        processID: UUID,
        dateProvider: DateProvider
    ) {
        self.featureScope = featureScope
        self.fatalErrorContext = fatalErrorContext
        self.processID = processID
        self.dateProvider = dateProvider
    }

    func startHang(hang: AppHang) {
        guard let lastRUMView = fatalErrorContext.view else {
            DD.logger.debug("App Hang is being detected, but won't be considered fatal as there is no active RUM view")
            return // TODO: RUM-3840 Track fatal App Hangs if there is no active RUM view
        }

        featureScope.rumDataStoreContext { [processID] context, dataStore in
            let fatalHang = FatalAppHang(
                processID: processID,
                hang: hang,
                serverTimeOffset: context.serverTimeOffset,
                lastRUMView: lastRUMView,
                trackingConsent: context.trackingConsent,
                appLaunchDate: context.launchTime?.launchDate
            )
            dataStore.setValue(fatalHang, forKey: .fatalAppHangKey)
        }
    }

    func cancelHang() {
        featureScope.rumDataStoreContext { _, dataStore in // on context queue to avoid race condition with `startHang(hang:)`
            dataStore.removeValue(forKey: .fatalAppHangKey)
        }
    }

    func endHang() {
        featureScope.rumDataStoreContext { _, dataStore in // on context queue to avoid race condition with `startHang(hang:)`
            dataStore.removeValue(forKey: .fatalAppHangKey)
        }
    }

    func reportFatalAppHangIfFound() {
        featureScope.rumDataStore.value(forKey: .fatalAppHangKey) { [weak self] (fatalHang: FatalAppHang?) in
            guard let fatalHang = fatalHang else {
                DD.logger.debug("No pending App Hang found")
                return // previous process didn't end up with a hang
            }
            guard fatalHang.processID != self?.processID else {
                return // skip as possible false-positive
            }
            self?.send(fatalHang: fatalHang)
        }
    }

    private func send(fatalHang: FatalAppHang) {
        guard fatalHang.trackingConsent == .granted else { // consider the user consent from previous session
            DD.logger.debug("Skipped sending fatal App Hang as it was recorded with \(fatalHang.trackingConsent) consent")
            return
        }

        featureScope.eventWriteContext(bypassConsent: true) { [dateProvider] context, writer in // bypass the current consent
            // Below we only consider the "happy path" scenario, when fatal App Hang has occurred within an active RUM session
            // with an existing active view and the app was restarted in less than `viewEventAvailabilityThreshold` after
            // termination. This is only subset of logic implemented for RUM crashes in `RUM.CrashReportReceiver`.
            //
            // Remaining edge cases include:
            // - sending fatal App Hang if there was no active view in previous RUM session (vs BET enabled or not)
            // - sending fatal App Hang before RUM session has started (vs "in foreground" or "in background" vs BET enabled or not)
            //
            // There is an oportunity for covering these cases through massive code reuse between fatal hangs and crashes through `FatalErrorBuilder`.
            // TODO: RUM-3840 Track fatal App Hangs if there is no active RUM view

            let realErrorDate = fatalHang.hang.startDate.addingTimeInterval(fatalHang.serverTimeOffset)
            let realDateNow = dateProvider.now.addingTimeInterval(context.serverTimeOffset)

            var timeSinceAppStart: TimeInterval? = nil
            if let startTime = fatalHang.appLaunchDate {
                timeSinceAppStart = realErrorDate.timeIntervalSince(startTime) * 1_000
            }


            let builder = FatalErrorBuilder(
                context: context,
                error: .hang,
                errorDate: realErrorDate,
                errorType: AppHangsMonitor.Constants.appHangErrorType,
                errorMessage: AppHangsMonitor.Constants.appHangErrorMessage,
                errorStack: fatalHang.hang.backtraceResult.stack,
                errorThreads: fatalHang.hang.backtraceResult.threads?.toRUMDataFormat,
                errorBinaryImages: fatalHang.hang.backtraceResult.binaryImages?.toRUMDataFormat,
                errorWasTruncated: fatalHang.hang.backtraceResult.wasTruncated,
                errorMeta: nil,
                timeSinceAppStart: timeSinceAppStart
            )
            let error = builder.createRUMError(with: fatalHang.lastRUMView)
            let view = builder.updateRUMViewWithError(fatalHang.lastRUMView)

            if realDateNow.timeIntervalSince(realErrorDate) < FatalErrorBuilder.Constants.viewEventAvailabilityThreshold {
                DD.logger.debug("Sending fatal App hang as RUM error with issuing RUM view update")
                // It is still OK to send RUM view to previous RUM session.
                writer.write(value: error)
                writer.write(value: view)
            } else {
                // We know it is too late for sending RUM view to previous RUM session as it is now stale on backend.
                // To avoid inconsistency, we only send the RUM error.
                DD.logger.debug("Sending fatal App hang as RUM error without updating RUM view")
                writer.write(value: error)
            }
        }
    }
}
