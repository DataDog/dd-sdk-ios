/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "AppDelegate.h"
@import DatadogObjc;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *clientToken = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"DatadogClientToken"];

    DDAppContext *appContext = [[DDAppContext alloc] initWithMainBundle: [NSBundle mainBundle]];
    DDConfigurationBuilder *builder = [DDConfiguration builderWithClientToken: clientToken];
    [builder setWithEndpoint: [DDLogsEndpoint us]];
    DDConfiguration *configuration = [builder build];

    [DDDatadog initializeWithAppContext:appContext configuration:configuration];
    [DDDatadog setVerbosityLevel: DDSDKVerbosityLevelDebug];

    return YES;
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

@end
