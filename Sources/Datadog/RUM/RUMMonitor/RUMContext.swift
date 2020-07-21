/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct RUMContext {
    /// An ID of RUM application.
    let rumApplicationID: String
    /// An ID of current RUM session. May change over time.
    var sessionID: RUMUUID

    /// An ID of currently displayed view.
    var activeViewID: RUMUUID?
    /// An URI of currently displayed view.
    var activeViewURI: String?
    /// An ID of active user action.
    var activeUserActionID: RUMUUID?
}
