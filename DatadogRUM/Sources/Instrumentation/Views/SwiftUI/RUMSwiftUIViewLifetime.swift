/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@_spi(Internal)
import DatadogInternal

/// Binds SwiftUI callbacks to the feature that originally admitted them.
internal final class RUMSwiftUIViewLifetime {
    let owner: RUMContextHandoff.Owner
    private weak var core: DatadogCoreProtocol?
    private weak var feature: RUMFeature?

    @MainActor
    init?(feature: RUMFeature, core: DatadogCoreProtocol) {
        guard feature.isMultiSceneTrackingEnabled,
              feature.monitor.supportsOwnedSwiftUIViews,
              let owner = feature.rumContextHandoffOwner,
              owner.isValid,
              core.get(feature: RUMFeature.self) === feature else {
            return nil
        }
        self.owner = owner
        self.core = core
        self.feature = feature
    }

    /// This check never acquires UI state or adopts a replacement feature.
    func isValid(for monitor: Monitor) -> Bool {
        guard owner.isValid, let core, let feature else {
            return false
        }
        return feature.monitor === monitor
            && feature.rumContextHandoffOwner === owner
            && core.get(feature: RUMFeature.self) === feature
    }
}

/// One context-queue publication; only admitted production retains the Monitor.
internal final class RUMSwiftUIViewContextPublication {
    private weak var monitor: Monitor?
    private let lifetime: RUMSwiftUIViewLifetime
    private var admittedMonitor: Monitor?

    init(monitor: Monitor, lifetime: RUMSwiftUIViewLifetime) {
        self.monitor = monitor
        self.lifetime = lifetime
    }

    func admit() -> Bool {
        guard let monitor, lifetime.isValid(for: monitor) else {
            return false
        }
        admittedMonitor = monitor
        return true
    }

    func context(using makeContext: (Monitor) -> RUMCoreContext?) -> RUMCoreContext? {
        guard let monitor = admittedMonitor else {
            return nil
        }
        defer { admittedMonitor = nil }
        return makeContext(monitor)
    }
}
#endif
