/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 13.0, *)
extension Image {
    public static var datadogLogo: Image {
        Image("dd_logo", bundle: .module)
    }

    public static var flowers: Image {
        Image("Flowers_1", bundle: .module)
    }
}
