/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogWebViewTracking;
@import WebKit;

@interface WebViewMock: WKWebView
@end

@implementation WebViewMock
@end

// MARK: - DDWebViewTracking tests

@interface DDWebViewTracking_apiTests : XCTestCase
@end

/*
 * `WebViewTracking` APIs smoke tests - minimal assertions, mainly check if the interface is available to Objc.
 */
@implementation DDWebViewTracking_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testDDWebViewTrackingAPI {
    WebViewMock *webView = [WebViewMock new];
    [DDWebViewTracking enableWithWebView:webView
                                   hosts:[NSSet<NSString*> setWithArray:@[@"host1.com", @"host2.com"]]
                          logsSampleRate:100.0
                                    with:nil];
    [DDWebViewTracking disableWithWebView:webView];
}

- (void)testDDWebViewTrackingSessionReplayConfigurationAPI {
    DDWebViewTrackingSessionReplayConfiguration *config = [[DDWebViewTrackingSessionReplayConfiguration alloc] init];
    XCTAssertEqual(config.privacyLevel, DDPrivacyLevelMask);
    config.privacyLevel = DDPrivacyLevelAllow;
    XCTAssertEqual(config.privacyLevel, DDPrivacyLevelAllow);
    config.privacyLevel = DDPrivacyLevelMaskUserInput;
    XCTAssertEqual(config.privacyLevel, DDPrivacyLevelMaskUserInput);
}

#pragma clang diagnostic pop

@end
