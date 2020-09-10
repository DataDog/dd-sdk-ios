/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMAutoInstrumentation {
    static var instance: RUMAutoInstrumentation?

    // TODO: RUMM-713 Store the UIKitRUMViewsHandler on property
    // TODO: RUMM-717 Store the UIKitRUMUserActionsHandler on property
    // TODO: RUMM-718 Store the RUMResourceHandler on property

    init?(with configuration: FeaturesConfiguration.RUM.AutoInstrumentation) {
    }

    func subscribe(commandSubscriber: RUMCommandSubscriber) {
        // TODO: RUMM-713 Pass the weak reference to `commandSubscriber` to `uiKitRUMViewsHandler`
        // TODO: RUMM-717 Pass the weak reference to `commandSubscriber` to `uiKitRUMUserActionsHandler`
        // TODO: RUMM-718 Pass the weak reference to `commandSubscriber` to `uiKitRUMResourceHandler`
    }
}
