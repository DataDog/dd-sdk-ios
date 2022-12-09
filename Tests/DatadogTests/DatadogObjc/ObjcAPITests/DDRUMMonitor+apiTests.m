/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

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

- (void)testDDRUMUserActionTypeAPI {
    DDRUMUserActionTypeTap; DDRUMUserActionTypeScroll; DDRUMUserActionTypeSwipe; DDRUMUserActionTypeCustom;
}

- (void)testDDRUMResourceTypeAPI {
    DDRUMResourceTypeImage; DDRUMResourceTypeXhr; DDRUMResourceTypeBeacon; DDRUMResourceTypeCss; DDRUMResourceTypeDocument;
    DDRUMResourceTypeFetch; DDRUMResourceTypeFont; DDRUMResourceTypeJs; DDRUMResourceTypeMedia; DDRUMResourceTypeOther;
    DDRUMResourceTypeNative;
}

- (void)testDDRUMMethodAPI {
    DDRUMMethodPost; DDRUMMethodGet; DDRUMMethodHead; DDRUMMethodPut; DDRUMMethodDelete; DDRUMMethodPatch;
}

- (void)testDDRUMMonitorAPI {
    UIViewController *anyVC = [UIViewController new];

    DDRUMMonitor *monitor = [DDRUMMonitor new];
    [monitor startViewWithViewController:anyVC name:@"" attributes:@{}];
    [monitor stopViewWithViewController:anyVC attributes:@{}];
    [monitor startViewWithKey:@"" name:nil attributes:@{}];
    [monitor stopViewWithKey:@"" attributes:@{}];
    [monitor addErrorWithMessage:@"" source:DDRUMErrorSourceCustom stack:nil attributes:@{}];
    [monitor addErrorWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:-100 userInfo:nil]
                        source:DDRUMErrorSourceNetwork attributes:@{}];
    [monitor startResourceLoadingWithResourceKey:@"" request:[NSURLRequest new] attributes:@{}];
    [monitor startResourceLoadingWithResourceKey:@"" url:[NSURL new] attributes:@{}];
    [monitor startResourceLoadingWithResourceKey:@"" httpMethod:DDRUMMethodGet urlString:@"" attributes:@{}];
    [monitor addResourceMetricsWithResourceKey:@"" metrics:[NSURLSessionTaskMetrics new] attributes:@{}];
    [monitor stopResourceLoadingWithResourceKey:@"" response:[NSURLResponse new] size:nil attributes:@{}];
    [monitor stopResourceLoadingWithResourceKey:@"" statusCode:nil kind:DDRUMResourceTypeOther size:nil attributes:@{}];
    [monitor stopResourceLoadingWithErrorWithResourceKey:@""
                                                   error:[NSError errorWithDomain:NSURLErrorDomain code:-99 userInfo:nil] response:nil attributes:@{}];
    [monitor stopResourceLoadingWithErrorWithResourceKey:@"" errorMessage:@"" response:nil attributes:@{}];
    [monitor startUserActionWithType:DDRUMUserActionTypeSwipe name:@"" attributes:@{}];
    [monitor stopUserActionWithType:DDRUMUserActionTypeSwipe name:nil attributes:@{}];
    [monitor addUserActionWithType:DDRUMUserActionTypeTap name:@"" attributes:@{}];
    [monitor addAttributeForKey:@"" value:@""];
}

#pragma clang diagnostic pop

@end
