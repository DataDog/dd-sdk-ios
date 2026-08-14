/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit

// MARK: - Application
internal typealias DDApplication = UIApplication
#elseif canImport(AppKit)
import AppKit

// MARK: - Application
internal typealias DDApplication = NSApplication
#endif
