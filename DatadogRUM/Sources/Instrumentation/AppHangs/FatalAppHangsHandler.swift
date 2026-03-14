/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class FatalAppHangsHandler:  @unchecked Sendable {
    /// RUM feature scope.
    private let featureScope: FeatureScope
    /// RUM context for fatal App Hangs monitoring.
    private let fatalErrorContext: FatalErrorContextNotifying
    /// An ID of the current process.
    private let processID: UUID
    /// Device date provider.
    private let dateProvider: DateProvider
    private let uuidGenerator: RUMUUIDGenerator

    init(
        featureScope: FeatureScope,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        dateProvider: DateProvider,
        uuidGenerator: RUMUUIDGenerator
    ) {
        self.featureScope = featureScope
        self.fatalErrorContext = fatalErrorContext
        self.processID = processID
        self.dateProvider = dateProvider
        self.uuidGenerator = uuidGenerator
    }

    func startHang(hang: AppHang) {
        guard let lastRUMView = fatalErrorContext.view else {
            DD.logger.debug("App Hang is being detected, but won't be considered fatal as there is no active RUM view")
            return // TODO: RUM-3840 Track fatal App Hangs if there is no active RUM view
        }

        Task { [processID, featureScope] in
            guard let context = await featureScope.context() else { return }
            let fatalHang = FatalAppHang(
                processID: processID,
                hang: hang,
                serverTimeOffset: context.serverTimeOffset,
                lastRUMView: lastRUMView,
                trackingConsent: context.trackingConsent,
                appLaunchDate: context.launchInfo.processLaunchDate
            )
            featureScope.rumDataStore.setValue(fatalHang, forKey: .fatalAppHangKey)
        }
    }

    func cancelHang() {
        featureScope.rumDataStore.removeValue(forKey: .fatalAppHangKey)
    }

    func endHang() {
        featureScope.rumDataStore.removeValue(forKey: .fatalAppHangKey)
    }

    func reportFatalAppHangIfFound() {
        // Report pending app hang
        Task { [weak self] in
            guard let self else { return }
            let fatalHang: FatalAppHang? = await self.featureScope.rumDataStore.value(forKey: .fatalAppHangKey)
            guard let fatalHang else {
                DD.logger.debug("No pending App Hang found")
                return // previous process didn't end up with a hang
            }
            guard fatalHang.processID != self.processID else {
                return // skip as possible false-positive
            }
            await self.send(fatalHang: fatalHang)
        }

        // Remove pending app hang
        featureScope.rumDataStore.removeValue(forKey: .fatalAppHangKey)
    }

    private func send(fatalHang: FatalAppHang) async {
        guard fatalHang.trackingConsent == .granted else {
            DD.logger.debug("Skipped sending fatal App Hang as it was recorded with \(fatalHang.trackingConsent) consent")
            return
        }

        guard let (context, writer) = await featureScope.eventWriteContext(bypassConsent: true) else { return }

        let realErrorDate = fatalHang.hang.startDate.addingTimeInterval(fatalHang.serverTimeOffset)
        let realDateNow = dateProvider.now.addingTimeInterval(context.serverTimeOffset)
        let timeSinceAppStart = fatalHang.appLaunchDate.map { realErrorDate.timeIntervalSince($0) }

        let builder = FatalErrorBuilder(
            context: context,
            error: .hang,
            errorUUID: uuidGenerator.generateUnique(),
            errorDate: realErrorDate,
            errorType: AppHangsMonitor.Constants.appHangErrorType,
            errorMessage: AppHangsMonitor.Constants.appHangErrorMessage,
            errorStack: fatalHang.hang.backtraceResult.stack,
            errorThreads: fatalHang.hang.backtraceResult.threads?.toRUMDataFormat,
            errorBinaryImages: fatalHang.hang.backtraceResult.binaryImages?.toRUMDataFormat,
            errorWasTruncated: fatalHang.hang.backtraceResult.wasTruncated,
            errorMeta: nil,
            additionalAttributes: nil,
            timeSinceAppStart: timeSinceAppStart
        )
        let error = builder.createRUMError(with: fatalHang.lastRUMView)
        let view = builder.updateRUMViewWithError(fatalHang.lastRUMView)

        if realDateNow.timeIntervalSince(realErrorDate) < FatalErrorBuilder.Constants.viewEventAvailabilityThreshold {
            DD.logger.debug("Sending fatal App hang as RUM error with issuing RUM view update")
            await writer.write(value: error)
            await writer.write(value: view)
        } else {
            DD.logger.debug("Sending fatal App hang as RUM error without updating RUM view")
            await writer.write(value: error)
        }
    }
}
