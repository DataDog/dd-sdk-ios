/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import "Runner-Swift.h"
#import "ObjcSendThirdPartyRequestsViewController.h"
@import DatadogTrace;

@interface ObjcSendThirdPartyRequestsViewController ()
@property URLSessionBaseScenario *testScenario;
@property NSURLSession *session;
@end

@implementation ObjcSendThirdPartyRequestsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.testScenario = SwiftGlobals.currentTestScenario;
    self.session = [self.testScenario getURLSession];
    assert(self.testScenario != nil);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self callThirdPartyURL];
    [self callThirdPartyURLRequest];
}

- (void)callThirdPartyURL {
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.thirdPartyURL];
    [task resume];
}

- (void)callThirdPartyURLRequest {
    NSURLSessionTask *task = [self.session dataTaskWithRequest:self.testScenario.thirdPartyRequest];
    [task resume];
}

@end
