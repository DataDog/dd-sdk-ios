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

    init(
        featureScope: FeatureScope,
        fatalErrorContext: FatalErrorContextNotifier,
        processID: UUID
    ) {
        self.featureScope = featureScope
        self.fatalErrorContext = fatalErrorContext
        self.processID = processID
    }

    func startHang(hang: AppHang) {
        guard let lastRUMView = fatalErrorContext.view else {
            DD.logger.debug("App Hang is being detected, but won't be considered fatal as there is no active RUM view")
            return // expected if there was no active view
        }

        featureScope.rumDataStoreContext { [processID] context, dataStore in
            let fatalHang = FatalAppHang(
                processID: processID,
                hang: hang,
                serverTimeOffset: context.serverTimeOffset,
                lastRUMView: lastRUMView
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
                return // previous process didn't end up with a hang
            }
            guard fatalHang.processID != self?.processID else {
                return // skip as possible false-positive
            }

            DD.logger.debug("Loaded fatal App Hang")

            self?.send(fatalHang: fatalHang)
        }
    }

    private func send(fatalHang: FatalAppHang) {
        // TODO: RUM-3461
        // Similar to how we send Crash report in `CrashReportReceiver`:
        // - construct RUM error from `fatalHang.hang` information
        // - update `error.count` in `fatalHang.lastRUMView`
    }
}
