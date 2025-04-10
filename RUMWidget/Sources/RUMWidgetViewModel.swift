/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogInternal
import DatadogRUM
import Foundation

@available(iOS 15.0, *)
public final class RUMWidgetViewModel: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var isHighlighted = false

    let configuration: Datadog.Configuration

    private let rumFeature: RUMFeature

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default,
        configuration: Datadog.Configuration
    ) {
        rumFeature = core.get(feature: RUMFeature.self)!
        self.configuration = configuration
    }
}
