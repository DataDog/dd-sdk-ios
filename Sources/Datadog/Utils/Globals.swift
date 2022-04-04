/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if SPM_BUILD
import _Datadog_Private
#endif

/// Function printing `String` content to console.
public var consolePrint: (String) -> Void = { print($0) }

/// Exception handler rethrowing `NSExceptions` to Swift `NSError`.
internal var objcExceptionHandler = __dd_private_ObjcExceptionHandler()
