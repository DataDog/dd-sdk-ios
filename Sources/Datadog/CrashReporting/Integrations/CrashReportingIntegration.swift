/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

/// An integration for sending crash reports to Datadog.
internal protocol CrashReportingIntegration {
    func send(crashReport: DDCrashReport, with crashContext: CrashContext)
}
