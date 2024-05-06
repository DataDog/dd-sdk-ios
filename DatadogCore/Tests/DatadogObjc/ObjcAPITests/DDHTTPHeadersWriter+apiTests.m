/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

@interface DDHTTPHeadersWriter_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDHTTPHeadersWriter_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testInitWithSamplingRate {
    [[DDHTTPHeadersWriter alloc] initWithSamplingStrategy:[DDTraceSamplingStrategy headBased]];
    [[DDHTTPHeadersWriter alloc] initWithSamplingStrategy:[DDTraceSamplingStrategy customWithSampleRate:50]];
}

#pragma clang diagnostic pop

@end
