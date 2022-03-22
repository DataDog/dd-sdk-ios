/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <CoreFoundation/CoreFoundation.h>

/// Returns the time interval between startup of the application process and the
/// `UIApplicationDidBecomeActiveNotification`.
///
/// If the `UIApplicationDidBecomeActiveNotification` has not been reached yet,
/// it returns  time interval between startup of the application process and now.
CFTimeInterval __dd_private_AppLaunchTime(void);

/// Returns `true` when the application is pre-warmed.
///
/// System sets environment variable `ActivePrewarm` to 1 when app is pre-warmed.
BOOL __dd_private_isActivePrewarm(void);
