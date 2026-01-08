/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogLogs;

@interface DDLogs_apiTests : XCTestCase
@end

/*
 * Objc API for smoke tests - minimal assertions, mainly check if the interface is available to Objc.
 */
@implementation DDLogs_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"
#pragma clang diagnostic ignored "-Wunused-variable"

- (void)testDDLogsAPI {
    DDLogsConfiguration *config = [[DDLogsConfiguration alloc] init];
    [DDLogs enableWith:config];

    [DDLogs addAttributeForKey:@"key1" value:@"value"];
    [DDLogs addAttributeForKey:@"key2" value:@1];
    [DDLogs addAttributeForKey:@"key3" value:@YES];
    [DDLogs addAttributeForKey:@"key4" value:@[@"array"]];
    [DDLogs addAttributeForKey:@"key5" value:@{@"key": @"value"}];

    [DDLogs removeAttributeForKey:@"key1"];
    [DDLogs removeAttributeForKey:@"keyNotAdded"];
}

- (void)testDDLogsConfigurationAPI {
    DDLogsConfiguration *config = [[DDLogsConfiguration alloc] initWithCustomEndpoint:nil];

    XCTAssertNil(config.customEndpoint);
    config.customEndpoint = [NSURL URLWithString:@"custom-endpoint"];
    XCTAssertNotNil(config.customEndpoint);

    [config setEventMapper:^DDLogEvent * (DDLogEvent* logEvent) {
        logEvent.message = @"log message";
        return logEvent;
    }];
}

- (void)testDDLoggerAPI {
    DDLoggerConfiguration *config = [[DDLoggerConfiguration alloc] init];

    DDLogger* logger = [DDLogger createWith:config];
    [logger addAttributeForKey:@"key" value:@"value"];
    [logger removeAttributeForKey:@"key"];
    [logger addTagWithKey:@"key" value:@"value"];
    [logger removeTagWithKey:@"key"];
    [logger addWithTag:@"foo"];
    [logger removeWithTag:@"foo"];

    [logger debug:@"debug"];
    [logger debug:@"debug" attributes:@{}];
    [logger debug:@"debug" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
    [logger info:@"info"];
    [logger info:@"info" attributes:@{}];
    [logger info:@"info" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
    [logger notice:@"notice"];
    [logger notice:@"notice" attributes:@{}];
    [logger notice:@"notice" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
    [logger warn:@"warn"];
    [logger warn:@"warn" attributes:@{}];
    [logger warn:@"warn" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
    [logger error:@"error"];
    [logger error:@"error" attributes:@{}];
    [logger error:@"error" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
    [logger critical:@"critical"];
    [logger critical:@"critical" attributes:@{}];
    [logger critical:@"critical" error: [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] attributes:@{}];
}

- (void)testDDLoggerConfigurationAPI {
    DDLoggerConfiguration *config = [[DDLoggerConfiguration alloc]
                                     initWithService:nil
                                     name:nil
                                     networkInfoEnabled:NO
                                     bundleWithRumEnabled:NO
                                     bundleWithTraceEnabled:NO
                                     remoteSampleRate:0
                                     remoteLogThreshold:DDLogLevelDebug
                                     printLogsToConsole:NO];

    XCTAssertNil(config.service);
    config.service = @"service";
    XCTAssertNotNil(config.service);

    XCTAssertNil(config.name);
    config.name = @"name";
    XCTAssertNotNil(config.name);

    XCTAssertFalse(config.networkInfoEnabled);
    config.networkInfoEnabled = YES;
    XCTAssertTrue(config.networkInfoEnabled);

    XCTAssertFalse(config.bundleWithRumEnabled);
    config.bundleWithRumEnabled = YES;
    XCTAssertTrue(config.bundleWithRumEnabled);

    XCTAssertFalse(config.bundleWithTraceEnabled);
    config.bundleWithTraceEnabled = YES;
    XCTAssertTrue(config.bundleWithTraceEnabled);

    XCTAssertEqual(config.remoteSampleRate, 0);
    config.remoteSampleRate = 100;
    XCTAssertEqual(config.remoteSampleRate, 100);

    XCTAssertEqual(config.remoteLogThreshold, DDLogLevelDebug);
    config.remoteLogThreshold = DDLogLevelError;
    XCTAssertEqual(config.remoteLogThreshold, DDLogLevelError);

    XCTAssertFalse(config.printLogsToConsole);
    config.printLogsToConsole = YES;
    XCTAssertTrue(config.printLogsToConsole);
}


#pragma clang diagnostic pop

@end

