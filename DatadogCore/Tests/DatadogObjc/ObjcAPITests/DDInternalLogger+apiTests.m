/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

@interface DDInternalLogger_apiTests : XCTestCase
@end

/*
 * `DDInternalLogger` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDInternalLogger_apiTests

- (void)testDDInternalLogger {

    [DDInternalLogger consolePrint:@"" :DDCoreLoggerLevelWarn];
    [DDInternalLogger telemetryDebugWithId:@"" message:@""];
    [DDInternalLogger telemetryErrorWithId:@"" message:@"" kind:@"" stack:@""];
}

@end
