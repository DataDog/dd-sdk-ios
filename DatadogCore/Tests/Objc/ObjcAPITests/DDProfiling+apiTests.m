/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <XCTest/XCTest.h>

#if !TARGET_OS_WATCH && !TARGET_OS_OSX

@import DatadogProfiling;

@interface DDProfiling_apiTests : XCTestCase
@end

@implementation DDProfiling_apiTests

- (void)testDefaultConfiguration {
    DDProfilingConfiguration *configuration = [[DDProfilingConfiguration alloc] init];

    XCTAssertNil(configuration.customEndpoint);
    XCTAssertEqual(configuration.applicationLaunchSampleRate, 5);
    XCTAssertEqual(configuration.continuousSampleRate, 5);
    XCTAssertEqual(configuration.memorySampleRate, 0);
}

- (void)testCustomConfiguration {
    NSURL *endpoint = [NSURL URLWithString:@"https://example.com/profiles"];
    DDProfilingConfiguration *configuration = [[DDProfilingConfiguration alloc] initWithCustomEndpoint:endpoint
                                                                         applicationLaunchSampleRate:12.5
                                                                                continuousSampleRate:37.5];

    XCTAssertEqualObjects(configuration.customEndpoint, endpoint);
    XCTAssertEqual(configuration.applicationLaunchSampleRate, 12.5);
    XCTAssertEqual(configuration.continuousSampleRate, 37.5);

    configuration.customEndpoint = nil;
    configuration.applicationLaunchSampleRate = 0;
    configuration.continuousSampleRate = 100;
    configuration.memorySampleRate = 12.5;

    XCTAssertNil(configuration.customEndpoint);
    XCTAssertEqual(configuration.applicationLaunchSampleRate, 0);
    XCTAssertEqual(configuration.continuousSampleRate, 100);
    XCTAssertEqual(configuration.memorySampleRate, 12.5);
}

- (void)testEnableAPI {
    DDProfilingConfiguration *configuration = [[DDProfilingConfiguration alloc] init];
    [DDProfiling enableWith:configuration];
    [DDProfiling enableWith:configuration instanceName:@"profiling-test"];
    [DDProfiling enableWith:configuration instanceName:nil];
}

@end

#endif
