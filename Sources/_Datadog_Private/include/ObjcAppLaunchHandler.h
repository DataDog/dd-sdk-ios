/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <CoreFoundation/CFDate.h>

/// Returns the time interval between startup of the application process and the
/// `UIApplicationDidBecomeActiveNotification`.
///
/// If the `UIApplicationDidBecomeActiveNotification` has not been reached yet,
/// it returns  time interval between startup of the application process and now.
CFTimeInterval __dd_private_AppLaunchTime(void);
