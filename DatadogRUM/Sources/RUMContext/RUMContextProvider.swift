/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol RUMContextProvider: AnyObject {
    /// The RUM context local to this provider.
    var context: RUMContext { get }
    var attributes: [AttributeKey: AttributeValue] { get }
}

extension RUMContextProvider {
    var rumContextAttributes: [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [
            RUMCoreContext.IDs.applicationID: context.rumApplicationID,
            RUMCoreContext.IDs.sessionID: context.sessionID.toRUMDataFormat,
        ]

        if let activeViewID = context.activeViewID {
            attributes[RUMCoreContext.IDs.viewID] = [activeViewID.toRUMDataFormat]
        }

        if let activeViewName = context.activeViewName {
            attributes[RUMCoreContext.IDs.viewName] = [activeViewName]
        }

        return attributes
    }
}
