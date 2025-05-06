/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogRUM;

@interface DDRUMMonitor_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDRUMMonitor_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testDDRUMViewAPI {
    DDRUMView *view = [[DDRUMView alloc] initWithName:@"abc" attributes:@{@"foo": @"bar"}];
    XCTAssertEqual(view.name, @"abc");
    XCTAssertNotNil(view.attributes[@"foo"]); // TODO: RUMM-1583 assert with `XCTAssertEqual`
}

- (void)testDDRUMActionAPI {
    DDRUMAction *action = [[DDRUMAction alloc] initWithName:@"abc" attributes:@{@"foo": @"bar"}];
    XCTAssertEqual(action.name, @"abc");
    XCTAssertNotNil(action.attributes[@"foo"]); // TODO: RUMM-1583 assert with `XCTAssertEqual`
}

- (void)testDDRUMErrorSourceAPI {
    DDRUMErrorSourceSource; DDRUMErrorSourceNetwork; DDRUMErrorSourceWebview; DDRUMErrorSourceConsole; DDRUMErrorSourceCustom;
}

- (void)testDDRUMActionTypeAPI {
    DDRUMActionTypeTap; DDRUMActionTypeScroll; DDRUMActionTypeSwipe; DDRUMActionTypeCustom;
}

- (void)testDDRUMResourceTypeAPI {
    DDRUMResourceTypeImage; DDRUMResourceTypeXhr; DDRUMResourceTypeBeacon; DDRUMResourceTypeCss; DDRUMResourceTypeDocument;
    DDRUMResourceTypeFetch; DDRUMResourceTypeFont; DDRUMResourceTypeJs; DDRUMResourceTypeMedia; DDRUMResourceTypeOther;
    DDRUMResourceTypeNative;
}

- (void)testDDRUMMethodAPI {
    DDRUMMethodPost; DDRUMMethodGet; DDRUMMethodHead; DDRUMMethodPut; DDRUMMethodDelete; DDRUMMethodPatch; DDRUMMethodConnect;
    DDRUMMethodTrace; DDRUMMethodOptions;
}

- (void)testDDRUMMonitorAPI {
    UIViewController *anyVC = [UIViewController new];

    DDRUMMonitor *monitor = [DDRUMMonitor shared];
    [monitor currentSessionIDWithCompletion:^(NSString * _Nullable sessionID) {}];
    [monitor stopSession];

    [monitor startViewWithViewController:anyVC name:@"" attributes:@{}];
    [monitor stopViewWithViewController:anyVC attributes:@{}];
    [monitor startViewWithKey:@"" name:nil attributes:@{}];
    [monitor stopViewWithKey:@"" attributes:@{}];
    [monitor addErrorWithMessage:@"" stack:nil source:DDRUMErrorSourceCustom attributes:@{}];
    [monitor addErrorWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:-100 userInfo:nil]
                        source:DDRUMErrorSourceNetwork attributes:@{}];
    [monitor startResourceWithResourceKey:@"" request:[NSURLRequest new] attributes:@{}];
    [monitor startResourceWithResourceKey:@"" url:[NSURL new] attributes:@{}];
    [monitor startResourceWithResourceKey:@"" httpMethod:DDRUMMethodGet urlString:@"" attributes:@{}];
    [monitor addResourceMetricsWithResourceKey:@"" metrics:[NSURLSessionTaskMetrics new] attributes:@{}];
    [monitor stopResourceWithResourceKey:@"" response:[NSURLResponse new] size:nil attributes:@{}];
    [monitor stopResourceWithResourceKey:@"" statusCode:nil kind:DDRUMResourceTypeOther size:nil attributes:@{}];
    [monitor stopResourceWithErrorWithResourceKey:@""
                                                   error:[NSError errorWithDomain:NSURLErrorDomain code:-99 userInfo:nil] response:nil attributes:@{}];
    [monitor stopResourceWithErrorWithResourceKey:@"" message:@"" response:nil attributes:@{}];
    [monitor startActionWithType:DDRUMActionTypeSwipe name:@"" attributes:@{}];
    [monitor stopActionWithType:DDRUMActionTypeSwipe name:nil attributes:@{}];
    [monitor addActionWithType:DDRUMActionTypeTap name:@"" attributes:@{}];
    [monitor addAttributeForKey:@"key" value:@"value"];
    [monitor removeAttributeForKey:@"key"];
    [monitor addAttributes:@{@"string": @"value", @"integer": @1, @"boolean": @true}];
    [monitor removeAttributesForKeys:@[@"string",@"integer",@"boolean"]];
    [monitor addFeatureFlagEvaluationWithName: @"name" value: @"value"];

    [monitor setDebug:YES];
    [monitor setDebug:NO];
}

#pragma clang diagnostic pop

@end
