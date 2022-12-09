/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import "Example-Swift.h"
#import "ObjcSendFirstPartyRequestsViewController.h"
@import DatadogObjc;

@interface ObjcSendFirstPartyRequestsViewController ()
@property URLSessionBaseScenario *testScenario;
@property NSURLSession *session;
@end

@implementation ObjcSendFirstPartyRequestsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.testScenario = SwiftGlobals.currentTestScenario;

    self.session = [self.testScenario getURLSession];
    assert(self.testScenario != nil);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self callSuccessfullFirstPartyURL];
    [self callSuccessfullFirstPartyURLRequest];
    [self callBadFirstPartyURL];
}

- (void)callSuccessfullFirstPartyURL {
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.customGETResourceURL
                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
    }];
    [task resume];
}

- (void)callSuccessfullFirstPartyURLRequest {
    NSURLSessionTask *task = [self.session dataTaskWithRequest:self.testScenario.customPOSTRequest
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
    }];
    [task resume];
}

- (void)callBadFirstPartyURL {
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.badResourceURL];
    [task resume];
}

@end
