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

    [self callSuccessfullURLWithCompletionHandler: ^{
        [self callSuccessfullURLRequestWithCompletionHandler: ^{
            [self callBadURLWithCompletionHandler: ^{
                // TODO: RUMM-731 Make calls to non-completion handler APIs
            }];
        }];
    }];
}

- (void)callSuccessfullURLWithCompletionHandler:(void (^)(void))completionHandler {
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.customGETResourceURL
                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
        completionHandler();
    }];
    [task resume];
}

- (void)callSuccessfullURLRequestWithCompletionHandler:(void (^)(void))completionHandler {
    NSURLSessionTask *task = [self.session dataTaskWithRequest:self.testScenario.customPOSTRequest
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error == nil);
        completionHandler();
    }];
    [task resume];
}

- (void)callBadURLWithCompletionHandler:(void (^)(void))completionHandler {
    NSURLSessionTask *task = [self.session dataTaskWithURL:self.testScenario.badResourceURL
                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        assert(error != nil);
        completionHandler();
    }];
    [task resume];
}

/// Calls `NSURLSession` APIs which are currently not auto instrumented.
/// This is just a sanity check to make sure the `URLSession` swizzling works fine in different edge case usages of the `NSURLSession`.
- (void)useNotInstrumentedAPIs {
    NSURLRequest *badResourceRequest = [[NSURLRequest alloc] initWithURL:self.testScenario.badResourceURL];
    // Use APIs with no completion block:
    [[self.session dataTaskWithRequest:badResourceRequest] resume];
    [[self.session dataTaskWithURL:self.testScenario.badResourceURL] resume];
    // Nullify the completion handlers:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [[self.session dataTaskWithRequest:badResourceRequest completionHandler:nil] resume];
    [[self.session dataTaskWithURL:self.testScenario.badResourceURL completionHandler:nil] resume];
#pragma clang diagnostic pop
}

@end
