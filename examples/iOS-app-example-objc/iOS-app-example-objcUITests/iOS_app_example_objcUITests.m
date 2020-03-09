/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <XCTest/XCTest.h>

@interface iOS_app_example_objcUITests : XCTestCase

@end

@implementation iOS_app_example_objcUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testExample {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [app launch];
}

@end
