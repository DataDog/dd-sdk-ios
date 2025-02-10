/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

private class ModuleClass { }

extension Bundle {
    static var module: Bundle { Bundle(for: ModuleClass.self) }
}

public let bundle: Bundle = .module
