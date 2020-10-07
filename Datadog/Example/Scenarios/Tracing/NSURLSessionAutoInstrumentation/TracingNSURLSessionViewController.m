/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#import "Example-Swift.h"
#import "TracingNSURLSessionViewController.h"
@import DatadogObjc;

@interface TracingNSURLSessionViewController()
@property TracingNSURLSessionScenario *testScenario;
@property NSURLSession *session;
@end

@implementation TracingNSURLSessionViewController

-(void)awakeFromNib {
    [super awakeFromNib];
    self.testScenario = SwiftGlobals.currentTestScenario;
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:[DDNSURLSessionDelegate new]
                                            delegateQueue:nil];

    assert(self.testScenario != nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self callSuccessfullFirstPartyURLWithCompletionHandler: ^{
        [self callSuccessfullFirstPartyURLRequestWithCompletionHandler: ^{
            [self callBadFirstPartyURL];
        }];
    }];

    [self callThirdPartyURL];
    [self callThirdPartyURLRequest];
}

- (void)callSuccessfullFirstPartyURLWithCompletionHandler:(void (^)(void))completionHandler {
    // This request is instrumented. It sends the `Span`.
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.customGETResourceURL
                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
        completionHandler();
    }];
    [task resume];
}

- (void)callSuccessfullFirstPartyURLRequestWithCompletionHandler:(void (^)(void))completionHandler {
    // This request is instrumented. It sends the `Span`.
    NSURLSessionTask *task = [self.session dataTaskWithRequest:self.testScenario.customPOSTRequest
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
        completionHandler();
    }];
    [task resume];
}

- (void)callBadFirstPartyURL {
    // This request is instrumented. It sends the `Span`.
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.badResourceURL];
    [task resume];
}

- (void)callThirdPartyURL {
    // This request is NOT instrumented. We test that it does not send the `Span`.
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.thirdPartyURL];
    [task resume];
}

- (void)callThirdPartyURLRequest {
    // This request is NOT instrumented. We test that it does not send the `Span`.
    NSURLSessionTask *task = [self.session dataTaskWithRequest:self.testScenario.thirdPartyRequest];
    [task resume];
}

@end
