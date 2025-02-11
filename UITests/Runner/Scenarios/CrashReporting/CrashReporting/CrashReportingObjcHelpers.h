/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CrashReportingObjcHelpers : NSObject

- (void) throwUncaughtNSException;
- (void) dereferenceNullPointer;

@end

NS_ASSUME_NONNULL_END
