/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(UIKit)
import UIKit

public typealias DDColor = UIColor
#if !os(watchOS)
public typealias DDView = UIView
#endif
#elseif canImport(AppKit)
import AppKit

public typealias DDColor = NSColor
public typealias DDView = NSView
#endif
