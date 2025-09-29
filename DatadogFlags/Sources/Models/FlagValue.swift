/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public protocol FlagValue {}

extension Bool: FlagValue {}
extension String: FlagValue {}
extension Int: FlagValue {}
extension Double: FlagValue {}
extension AnyValue: FlagValue {}
